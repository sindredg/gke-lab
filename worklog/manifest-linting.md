# Manifest linting

Date: 2026-09-16

kube-linter ran on every pull request since Phase 3, advisory, with its exit code discarded. The plan was to make it blocking once Phases 4 and 5 closed its findings. That never happened, so four findings sat in run summaries nobody had to read.

## Findings

| Check | Object | Verdict |
| --- | --- | --- |
| `pdb-unhealthy-pod-eviction-policy` | `PodDisruptionBudget/nginx`, `PodDisruptionBudget/sky` | Real. Fixed. |
| `no-read-only-root-fs` | `Deployment/nginx` | Real. Fixed. |
| `no-anti-affinity` | `Deployment/nginx` | Disagreement. Excluded. |

The disruption budgets used the default `IfHealthyBudget`, which refuses to evict a Pod while the budget is unmet, even a Pod that is not Ready and serves nothing. A crashlooping replica could then hold a node drain, which is the upgrade path [Phase 9](phase-09-resilience.md) depends on. Both now set `unhealthyPodEvictionPolicy: AlwaysAllow`.

sky already ran with a read-only root filesystem. nginx did not.

`no-anti-affinity` only recognises `podAntiAffinity`. Replicas here spread with `topologySpreadConstraints`, for the reasons in [replica placement](../decisions.md#replica-placement). The check fired on nginx and not on sky only because sky has no `replicas` field for it to read. It is excluded in `.kube-linter.yaml`.

## Read-only nginx, proven locally first

The [base image decision](../decisions.md#base-image) records this failure shape: a container that starts and then fails. So the image built from `app/` ran under `docker run --read-only` before any manifest changed.

The image says where it writes. `nginx.conf` puts the PID and every temp path under `/tmp`, and the entrypoint renders the template into `/etc/nginx/conf.d`.

| Run | Writable | Result |
| --- | --- | --- |
| B | nothing | Exit 1. `can't create /etc/nginx/conf.d/default.conf: Read-only file system` |
| A | `/tmp` | Exit 1. Same error. |
| C | `conf.d` | Exit 1. `mkdir() "/tmp/proxy_temp" failed (30: Read-only file system)` |
| D | `/tmp`, `conf.d` as Docker's default tmpfs | **Running, no listener.** Connection refused on 8080, no error in the nginx log. |
| E | `/tmp`, `conf.d` at mode 1777 | `/healthz` 200, page 3,824 bytes, no placeholders left, uid 101 shown, `touch /` refused. |

Run D is the one worth keeping. Docker mounts a tmpfs as `root:root 775`, which uid 101 cannot write. The entrypoint logged `ERROR: /etc/nginx/templates exists, but /etc/nginx/conf.d is not writable` and carried on. nginx then started with no server block, listening on nothing, and reported healthy worker processes. A process check would pass. Only a request fails.

A Kubernetes `emptyDir` is created world-writable, which is what run E reproduces. If a volume ever came up unwritable, the readiness probe on `/healthz` would never pass, the Pod would never become Ready, and `maxUnavailable: 0` would keep the old Pods serving. That is the containment the [rollout drill](phase-10-failure-drills.md) proved.

## The gate

`ci.yml` now runs `kube-linter lint --config .kube-linter.yaml kubernetes/` inside the `Kubernetes` job, which the ruleset on `main` already requires.

| Injected | Result |
| --- | --- |
| none | `No lint errors found!`, exit 0 |
| `unhealthyPodEvictionPolicy` removed from the sky budget | `pdb-unhealthy-pod-eviction-policy`, exit 1 |
| `readOnlyRootFilesystem` removed from nginx | `no-read-only-root-fs`, exit 1 |
| an empty config in place of `.kube-linter.yaml` | `no-anti-affinity`, exit 1 |

The last row shows the exclusion suppresses one check and nothing else.

## In the cluster

The budgets are not in the pipeline, so they were applied by hand:

```bash
kubectl apply -f kubernetes/nginx/poddisruptionbudget.yml -f kubernetes/sky/poddisruptionbudget.yml
```

```
poddisruptionbudget.policy/nginx configured
poddisruptionbudget.policy/sky configured
```

Merging [#85](https://github.com/sindredg/k8-lab/pull/85) triggered `Deploy` on its own, although it changed no file under `app/`. That is the first manifest-only nginx change to deploy on merge, and it is what [#84](https://github.com/sindredg/k8-lab/pull/84) was for. Run [35086307973](https://github.com/sindredg/k8-lab/actions/runs/35086307973) finished at 10:43:31 UTC, rollout and smoke test included. The edge then served `/healthz` with a 200, and the page with digest `sha256:254f0ebc…` and no placeholders left, so nginx had rendered its config into the `emptyDir`.

### The first check proved nothing

Run before the deploy had finished, against the Pods from the previous build:

```bash
kubectl exec -n demo deploy/nginx -- touch /should-fail
```

```
touch: /should-fail: Permission denied
```

It looked like a pass, and it was not one. `/` is owned by root, so uid 101 is refused there whether or not the filesystem is read-only. A read-only mount refuses the write before permissions are checked, and says so: the local run printed `Read-only file system`. `Permission denied` meant the root was still writable. The Deploy run for #85 was still waiting for a runner.

A check that separates the two has to write somewhere the process owns. `/var/cache/nginx` belongs to uid 101, so on a writable root the write succeeds.

### After the deploy

```bash
kubectl get deploy nginx -n demo -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}{"\n"}'
kubectl get pods -n demo -l app.kubernetes.io/name=nginx
kubectl exec -n demo deploy/nginx -- touch /var/cache/nginx/probe
kubectl exec -n demo deploy/nginx -- sh -c 'touch /tmp/probe && ls /etc/nginx/conf.d'
```

| Check | Result |
| --- | --- |
| `readOnlyRootFilesystem` in the live spec | `true` |
| Pods | `nginx-54444fc956-q282q` and `-rb7q7`, both `1/1 Running`, 0 restarts |
| Write to a directory uid 101 owns | `Read-only file system` |
| Write to `/tmp`, then list `conf.d` | no error, `default.conf` |

## Open

- **The entrypoint continues on an unwritable `conf.d`.** That is upstream behaviour. The readiness probe is what catches it here.

# Operations reference

Who changes what, and how a change reaches the cluster.

## What each path applies

A merge to `main` deploys only what a pipeline applies. Everything else waits for an operator, and CI says so on the pull request.

| Path | Applied by | How |
| --- | --- | --- |
| `terraform/` | Operator | `terraform -chdir=terraform plan`, read it, then `apply`. Never apply a plan that destroys something without reading it: the public certificate lives in this state |
| `kubernetes/platform/*` | Operator | `./scripts/apply-operator-owned.sh platform`. Holds the pipeline's own Role, which is why no pipeline applies it |
| `kubernetes/nginx/deployment.yml` | [Deploy](../.github/workflows/deploy.yml) | On a merge touching `app/` or this file. Renders the digest it just built |
| `kubernetes/nginx/*`, the rest | Operator | `./scripts/apply-operator-owned.sh nginx` |
| `kubernetes/sky/deployment.yml` | [Deploy sky](../.github/workflows/deploy-sky.yml) | On a merge touching this file or `.github/sky-upstream.ref` |
| `kubernetes/sky/*`, the rest, including the HPA | Operator | `./scripts/apply-operator-owned.sh sky` |
| `kubernetes/agents/*` | Operator | `./scripts/apply-operator-owned.sh agents`. The pipeline holds no RBAC in `agents`, as [decisions.md](../decisions.md#agent-rollout-authority) records |
| Triage worker image | [Deploy triage worker](../.github/workflows/deploy-triage-worker.yml) | Built and published on a merge touching the ai-k8s pin or a corpus source. Not rolled out |
| `.github/sky-upstream.ref`, `.github/ai-k8s.ref` | Watch workflows propose, a person merges | The workflow pushes a `bump-*` branch. It cannot open the pull request, so it is opened by hand |

`./scripts/apply-operator-owned.sh` skips the two pipeline-owned Deployments. Their committed digest is the one they were bootstrapped with, so applying either by hand rolls the workload back.

## Rolling out the triage worker

The Deploy triage worker run prints the digest. The worker records `IMAGE_DIGEST` with every verdict, so the image and the variable move together, and CI fails when they differ.

```bash
./scripts/pin-worker-image.sh sha256:<digest>
kubectl apply -f kubernetes/agents/deployment.yml
kubectl rollout status deployment/triage-worker -n agents --timeout=180s
```

Commit the manifest change in the same pull request that records the rollout.

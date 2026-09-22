# Operations reference

Where configuration lives, the order to build the platform in, who applies what, and how to recover. The bootstrap order is reconstructed from the phase worklogs. It has not been rehearsed end to end on an empty project.

## Where values live

| Value | Lives in | Read by |
| --- | --- | --- |
| `project_id`, `project_number`, `domain`, `alert_email` | `terraform/terraform.tfvars`, ignored by git | Terraform. `region`, `zone` and `node_zones` have defaults in [variables.tf](../terraform/variables.tf) |
| Terraform state | `terraform/terraform.tfstate` on the operator's workstation, ignored by git | Terraform. There is no remote backend: copy the file somewhere safe after every apply |
| `WIF_PROVIDER`, `DEPLOY_SERVICE_ACCOUNT` | GitHub repository variables | The three deploy workflows. Set from the Terraform outputs `workload_identity_provider` and `deploy_service_account_email` |
| Project, region, cluster and image paths | Literals in the deploy workflows' `env` and in the manifests | `grep -rln project-69726555 .github kubernetes` lists every file to edit for another project |
| DNS, CAA and DNSSEC | Cloudflare, by hand | [Phase 7](../worklog/phase-07-gateway-tls.md) and [Phase 14](../worklog/phase-14-close-the-baseline.md) |
| Upstream pins | `.github/sky-upstream.ref`, `.github/ai-k8s.ref` | The deploy workflows. The watch workflows propose a new one |

## Bootstrap order

On an empty project with billing, from a workstation authenticated with `gcloud`:

1. **Infrastructure.** Write `terraform.tfvars`, then `terraform -chdir=terraform init` and `apply`. This enables the APIs and builds the network, cluster, registry, federation, Gateway address, certificate, SSL and Cloud Armor policies, observability, the findings path and the agent identity.
2. **DNS.** Add the `dns_authorization_record` output and an A record for `gateway_address` in Cloudflare. The certificate stays `PROVISIONING` until the authorization record resolves.
3. **Delivery.** Set the two repository variables from the Terraform outputs.
4. **Cluster access.** `gcloud container clusters get-credentials k8-lab --zone europe-north1-a --dns-endpoint`. The control plane has no IP endpoint.
5. **Platform manifests.** `./scripts/apply-operator-owned.sh platform`. This creates `demo`, its guardrails, the Gateway and the pipeline's Role. No pipeline can apply its own permissions.
6. **Workloads.** The deploy Role patches and does not create, so an operator creates each Deployment once, with a digest the registry holds. A fresh registry holds none of the committed digests.
   - `sky`: run Deploy sky with `build_only`, then `./scripts/apply-operator-owned.sh sky` and render `kubernetes/sky/deployment.yml` with the reported digest, `kubectl set image -f kubernetes/sky/deployment.yml --local -o yaml sky=<image>@<digest> | kubectl apply -f -`.
   - `nginx`: Deploy has no `build_only`. Run it: it publishes and then fails at the apply. Create the Deployment the same way from the digest in the run.
   - The triage worker: run Deploy triage worker, then `./scripts/pin-worker-image.sh <digest>` and `./scripts/apply-operator-owned.sh agents`.
7. **Check.** Each deploy workflow's smoke test, `./scripts/check-public-surface.sh <domain>`, and the uptime check on the dashboard.

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

## Recovery

| Failure | What happens | Recover |
| --- | --- | --- |
| A `nginx` or `sky` rollout never goes Ready | `maxUnavailable: 0` keeps the old Pods serving, and the workflow fails at `rollout status` | Revert the commit, or `kubectl rollout undo deployment/<name> -n demo`. [Phase 10](../worklog/phase-10-failure-drills.md) drilled this |
| A worker image is bad | The worker crash-loops, and findings wait on the subscription | `./scripts/pin-worker-image.sh` with the previous digest from `git log -p kubernetes/agents/deployment.yml`, then apply |
| The worker is down for a while | Findings wait on the subscription and are triaged on restart. After five failed deliveries a finding moves to `scc-findings-dead`, and the dead-letter alert fires | Nothing re-drives the dead letter topic. A parked finding returns when Security Command Center publishes it again: see [the backfill](../worklog/phase-15-scc-triage.md#slice-10-the-backfill-and-the-overlap-measured-by-the-worker) |
| The cluster is lost | Nothing in it is the only copy of anything. Verdicts live in the ledger bucket, images in the registry | `terraform apply`, then steps 4 to 7 of the bootstrap |
| Terraform state is lost | Terraform no longer knows what it created, and a plan proposes to create everything again | Restore the copy. Without one, `terraform import` each resource before any apply. The certificate carries `prevent_destroy` |
| The model misbehaves or its bill climbs | The daily spend ceiling stops calls and records the refusal as `insufficient_evidence` | Remove `-model` from the worker's arguments and apply. The rules still settle every finding |

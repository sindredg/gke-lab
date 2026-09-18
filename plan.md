# Secure GKE Workload Platform Plan

## Goal

Build and prove a secure GKE workload delivery platform. The platform is the portfolio project. An AI-assisted Kubernetes manifest reviewer will be a small reference workload after the first platform slice is complete.

## Current baseline

**Status:** Complete

- Modular Terraform foundation
- Custom VPC, private nodes, Cloud NAT, and DNS-only control plane endpoint
- GKE Dataplane V2 and Workload Identity Federation
- Autoscaling GKE Standard node pool
- `demo` namespace with an NGINX Deployment and ClusterIP Service
- Probes, resource controls, scaling, self-healing, restart, and rollback validation
- Credential-free pull request validation, required on `main`
- Deployment evidence in the Phase 1, Phase 2, and Phase 3 worklogs

The existing cluster, namespace, manifests, and evidence remain in use.

## Milestone 1: Complete platform slice

The first milestone takes the existing NGINX workload through validation, policy, image delivery, external access, observability, resilience, and failure testing.

### Phase 3: Credential-free CI

**Status:** Complete

- Run `terraform fmt -check`.
- Run `terraform init -backend=false` and `terraform validate`.
- Validate Kubernetes schemas.
- Report Kubernetes security findings without blocking until Phase 4 and Phase 5 close them.
- Require both checks and a pull request before merge.
- Do not grant the workflow Google Cloud credentials.

Deferred: YAML and Markdown linting, until a change needs them.

**Exit criteria met:** Invalid Terraform or Kubernetes changes fail in a pull request, and `main` rejects the merge.

Documentation: [Terraform automation](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform), [GitHub Actions](https://docs.github.com/en/actions), [kubeconform](https://github.com/yannh/kubeconform), [kube-linter](https://docs.kubelinter.io/)

### Phase 4: Guard the existing workload

**Status:** Complete

- Add a `ResourceQuota` and `LimitRange` to the existing namespace.
- Enforce the Pod Security Baseline.
- Audit and warn against the Restricted standard.
- Add default-deny NetworkPolicies.
- Allow only required DNS and application traffic.
- Add a dedicated Kubernetes ServiceAccount.
- Keep unnecessary service account token mounts disabled.

**Exit criteria met:** Required traffic works. Privileged Pods and oversized resource requests are rejected at admission. An unlabelled client is denied by name and by address, and egress outside the declared paths is dropped.

Documentation: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/), [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/), [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/), [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)

### Phase 5: Custom image and Artifact Registry

**Status:** Complete

- Turn the existing NGINX workload into a small project frontend.
- Build a non-root container image.
- Create Artifact Registry with Terraform.
- Scan the image and deploy it by immutable digest.
- Validate image pulls from the private node pool.

**Exit criteria met:** The workload runs a project-owned, non-root image pulled from Artifact Registry by digest. The container port moved to 8080 through the Deployment and both NetworkPolicies, and Pod Security enforces `restricted`, closing the gap Phase 4 left open.

Documentation: [Artifact Registry with GKE](https://cloud.google.com/artifact-registry/docs/integrate-gke), [Artifact Analysis](https://cloud.google.com/artifact-analysis/docs/container-scanning-overview), [GKE container security](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#container_security)

### Phase 6: Keyless application delivery

**Status:** Complete

- Configure Workload Identity Federation for GitHub Actions.
- Use a dedicated, least-privilege pipeline identity.
- Restrict trust to the intended repository and deployment context.
- Build, push, deploy, wait for rollout, and run a smoke test.
- Stop the workflow when rollout validation fails.

**Exit criteria met:** A push to `main` builds, publishes, and rolls out the image with no stored key. Trust is scoped to this repository by attribute condition, the pipeline identity holds a namespaced Role rather than a project role, and a rollout that does not become Ready stops the workflow before the smoke test runs.

Documentation: [Workload Identity Federation for deployment pipelines](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines), [pipeline service account practices](https://cloud.google.com/iam/docs/best-practices-for-using-service-accounts-in-deployment-pipelines)

### Phase 7: Gateway and HTTPS

**Status:** Complete

- Enable GKE Gateway API.
- Create an external Gateway and HTTPRoute.
- Reserve a static IP.
- Add DNS and managed TLS after the domain decision.
- Keep workload Services private.

**Exit criteria:** The workload is reachable through the Gateway while its Service remains internal. Met: `https://sindrg.com` returns `200` on a Google Trust Services certificate, port 80 redirects to it, and the Service is still `ClusterIP` with no external address, reached through a network endpoint group.

Documentation: [GKE Gateway API](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api), [deploy a Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways), [secure a Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway)

### Phase 8: Observability and evidence

**Status:** Complete

- Create one workload health dashboard.
- Create one actionable availability alert.
- Measure onboarding and deployment time.
- Capture an actual GCP cost snapshot.
- Write one short incident postmortem.

The deliberate failures are Phase 10.

**Exit criteria met:** Every platform claim below has recorded commands, results, and evidence.

| Claim | Evidence |
| --- | --- |
| Onboarding is repeatable | 59s from merge to Ready workload. [Phase 8](worklog/phase-08-observability.md) |
| Quotas work | Excessive request attempted and rejected. [Phase 4](worklog/phase-04-workload-guardrails.md) |
| Pod Security works | Privileged Pod attempted and rejected. [Phase 4](worklog/phase-04-workload-guardrails.md) |
| Network isolation works | Unauthorized connection attempted and denied. [Phase 4](worklog/phase-04-workload-guardrails.md) |
| Delivery is keyless | Successful pipeline run without stored cloud keys. [Phase 6](worklog/phase-06-keyless-delivery.md) |
| Rollout is controlled | Failed version detected and previous version restored. [Phase 10](worklog/phase-10-failure-drills.md) |
| Monitoring works | Deliberate failure triggered the expected alert. [Phase 10](worklog/phase-10-failure-drills.md) |
| Cost is understood | kr461.81 a week, three sources named. [Phase 8](worklog/phase-08-observability.md) |

Existing self-healing, scaling, restart, and rollback evidence counts toward this milestone.

Documentation: [GKE observability](https://cloud.google.com/kubernetes-engine/docs/concepts/observability), [Cloud Monitoring alerting](https://cloud.google.com/monitoring/alerts), [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)

### Phase 9: Surviving a node

**Status:** Complete

Two replicas survived a rollout and would not have survived a node going away.

- Raise the node pool floor to two, so a drained Pod has somewhere to land.
- Decouple `initial_node_count` from that floor, because it is `ForceNew` and moving it replaces the pool.
- Set a daily maintenance window, so node replacement is predictable rather than whenever the release channel arrives.
- Add a `PodDisruptionBudget` with `minAvailable: 1` to both workloads.
- Spread the Pods across both nodes, and record why a rolling restart does not do it.

**Exit criteria met:** Both workloads run a replica on each node, both budgets report one allowed disruption, and node replacement lands in a known window. `maxUnavailable: 0` already covered a rollout; the budgets cover an eviction, which is what `auto_upgrade` and `auto_repair` perform without asking.

Documentation: [PodDisruptionBudget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/), [Pod topology spread](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/), [GKE maintenance windows](https://cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions)

### Phase 10: Failure drills

**Status:** Complete

The first work here that adds nothing and only tests what exists.

- Take the site down deliberately and time the alert.
- Ship a knowingly broken version through the real pipeline.
- Record the detection lag rather than the intended one.
- Restore both, through the documented path.

**Exit criteria met:** The alert opened about 3m15s after the site stopped serving and closed on recovery. A broken `/healthz` reached the pipeline, failed the rollout gate at 3m1s, and never reached a user, because `maxUnavailable: 0` refuses to retire a healthy Pod for one that is not Ready.

Two limits are now written down rather than assumed. Detection cannot beat roughly 3 minutes, because the check runs every 60s per location, the condition needs more than one location failing, and `duration` holds it a further 60s. And CI passed the broken change, because it validates Terraform and Kubernetes schemas and nothing parses nginx configuration, so a runtime fault of this class is caught after the image is built rather than before.

Evidence: [Phase 10 worklog](worklog/phase-10-failure-drills.md)

Documentation: [Deployment strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy), [configure probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/), [uptime checks](https://cloud.google.com/monitoring/uptime-checks)

### Phase 11: Hardening and log analytics

**Status:** Complete

A security pass over what Milestone 1 built, before leaving the platform running unattended.

- Delete the unused `default` VPC, which was open to the internet on SSH and RDP.
- Turn on workload vulnerability scanning, which was off.
- Enable Log Analytics on logs already ingested and billed.
- Add one log-based metric, from a filter validated against real data rather than assumed.
- Redact the control plane endpoint from the public networking reference.
- Close the items Phase 9 left open: spread that survives a rollout, and a clean `terraform plan`.

**Exit criteria met:** `gke-vpc` is the only network and every rule on it is one GKE created. The cluster reports `VULNERABILITY_BASIC`. `_Default` reports analytics enabled. No node was replaced. `terraform plan` reports no changes for the first time in the project.

The audit found what it was looking for and then found something better. Planning the change surfaced a `ForceNew` drift on `initial_node_count` that would have destroyed both nodes on any apply, armed since Phase 9 raised the node floor by hand. Two limits are also recorded. `constraints/iam.disableServiceAccountKeyCreation` cannot be set by a project owner. Retuning the cost budget was rejected, because the account runs on credits and cannot turn usage into a charge, so the threshold guards nothing.

Evidence: [Phase 11 worklog](worklog/phase-11-hardening.md)

Documentation: [GKE security posture](https://cloud.google.com/kubernetes-engine/docs/concepts/about-security-posture-dashboard), [Log Analytics](https://cloud.google.com/logging/docs/analyze/query-and-view), [log-based metrics](https://cloud.google.com/logging/docs/logs-based-metrics), [organization policy constraints](https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints)

## Milestone 2: Load and autoscaling

Milestone 1 proved the platform under deliberate failure with close to no traffic. This milestone measures it under load, and proves the scaling path from a busy Pod to a new node.

### Phase 12: Load and autoscaling

**Status:** Complete

Every run uses the same scripts and every step changes one variable, so each difference in the results has one cause.

- Add the `CADVISOR`, `HPA`, `DEPLOYMENT` and `POD` metric packages, and dashboard panels for sky's desired and available replicas and its throttled CPU.
- Add `loadtest/`: a stepped k6 ramp, a constant-rate rollout test, and a recorder that captures the HPA, Deployments, Pods, nodes and events every 5s.
- Generate load from a VM in `europe-west4` on a throwaway VPC reached through IAP, created and deleted with gcloud each session.
- Calibrate before the baseline, so the load generator is never the bottleneck.

| Step | Change | Runs | Prediction |
| --- | --- | --- | --- |
| A | None | Ramp, rollout under load | sky saturates on its CPU limit first. A rollout drops requests, because nothing covers the time the load balancer takes to stop routing to a terminating Pod. |
| B | `preStop` sleep and a longer `terminationGracePeriodSeconds`, sized from A | Rollout under load | No errors during a rollout. |
| B2 | `--timeout-keep-alive 620` on sky and `keepalive_timeout 620s` on nginx, above the load balancer's 600s | Ramp | No 503s from closed backend connections. |
| C0 | None, with each ramp step judged after it settles | Ramp, 180s steps settled after 90s | Saturation near 40 rps: the fixed-replica reference C and D compare against. |
| C | HPA on sky, 2 to 8 replicas at 70% CPU, current quota | Ramp from 20 rps, 120s steps settled after 75s; a deploy under held load | Replicas stop at 5 from about 20 rps, where `limits.cpu` reaches 3000m of 3000m, while the HPA wants 8. Saturation near 100 rps, five Pods at C0's 20 each. A deploy during the stall fails at the rollout gate. Both recover once load stops. |
| D | sky request 350m and limit 1000m, quota for eight replicas at that size | Ramp from 20 rps, 120s steps settled after 75s | Throttling falls. The sixth Pod goes `Pending`, because two nodes have about 2000m of requests free, and a third node joins. Saturation above C's 60 rps. The pool returns to two nodes after load stops. |

Each step is one pull request. The worklog splits by concern: 12a for the baseline ramp, 12b for the baseline rollout, 12c for rollouts and connections (B, B2), and 12d for autoscaling (C, D).

- A ramp stops at the first step where p95 exceeds 500ms or errors exceed 1%, judged on the requests sent after the step settles: 15s into a 60s step, 90s into C0's 180s steps, and 75s into the 120s steps C and D use, so the HPA has time to act.
- `replicas` leaves sky's Deployment in C. Its last-applied record is edited first, or the pipeline's next apply drops sky to one Pod.
- The pipeline Role cannot create an HPA, so an operator applies it.
- The quota in D covers `maxReplicas`, one surge Pod, two old Pods still in their `preStop` sleep, the smoke test Pod and nginx, and `pods` rises with it. It is applied before the resized Deployment, or the resize's own rollout does not fit.
- The uptime alert stays armed.

Deferred: sudden node loss and drain under load, autoscaling nginx, and custom metrics.

**Exit criteria met:** Every run is recorded below and in its worklog. A rollout at 20 rps went from 73 failed requests to none. The HPA stalled at five of eight on the quota, a deploy during the stall failed, and both recovered once sky scaled down. Resized, eight Pods held 125 rps with no failures, and a Pod ran on a new node 97s after the HPA's decision. The load generator and its VPC are deleted, and `gke-vpc` is the only network.

| Run | Configuration | Saturation | p95 at saturation | Failed | Peak replicas | Nodes |
| --- | --- | --- | --- | --- | --- | --- |
| A ramp | 2 replicas, 100m and 500m | 40 rps | 230ms | 6 of 10,331 | 2 | 2 |
| A rollout | no `preStop` | | | 73 of 6,357, 20.4s window | 2 | 2 |
| B rollout | `preStop` 35s | | | 0 connection failures | 2 | 2 |
| B2 ramp | keep-alive 620s | | | 0 of 7,150 | 2 | 2 |
| C0 ramp | settled steps | 40 rps | 251ms | 0 of 34,187 | 2 | 2 |
| C ramp | HPA, quota 3 CPU | 60 rps | 240ms | 0 of 22,132 | 5 of 8 | 2 |
| D ramp | 350m and 1000m | 100 rps | 489ms | 0 of 47,951 | 4 of 8 | 2, zone out of capacity |
| D ramp, three zones | nodes in a, b, c | 125 rps | 394ms | 0 of 65,361 | 8 | 3 |
| Spike to 150 rps | liveness 5s, six failures | | | 18.2% of sky | 8 after 2m51s | 2 to 3 |

Two limits are written down rather than assumed. A spike above resting capacity fails requests until new capacity serves it, 2m51s from two nodes, and only capacity at rest removes that. And a scale-up into another zone during a shortage is configured and seen to work on a normal day, but cannot be triggered on demand.

Evidence: [Phase 12a worklog](worklog/phase-12a-load-baseline.md), [Phase 12b worklog](worklog/phase-12b-rollout-baseline.md), [Phase 12c worklog](worklog/phase-12c-rollouts-connections.md), [Phase 12d worklog](worklog/phase-12d-autoscaling.md)

Documentation: [Horizontal Pod Autoscaling](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/), [migrating a Deployment to an HPA](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/#migrating-deployments-and-statefulsets-to-horizontal-autoscaling), [container lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/), [container-native load balancing](https://cloud.google.com/kubernetes-engine/docs/concepts/container-native-load-balancing), [GKE cluster autoscaler](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler), [kube state metrics](https://cloud.google.com/kubernetes-engine/docs/how-to/kube-state-metrics), [cAdvisor and kubelet metrics](https://cloud.google.com/kubernetes-engine/docs/how-to/cadvisor-kubelet-metrics), [k6 executors](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/)

## Milestone 3: Security baseline and hardening

Phase 11 was a security pass by inspection, and it found real things. This milestone replaces inspection with measurement, because the two most recent findings arrived by routes inspection does not cover. A public TLS scan graded the load balancer `B` on a default SSL policy nobody had chosen, and writing a threat model showed that merge protection is not a control on the path to Google Cloud. Neither is visible by reading a manifest.

It runs before the AI workload rather than after. Accepting submitted YAML from the internet changes the threat model substantially, and a baseline is worth more established against the system as it stands than against one that is moving.

The frame is [the threat model](reference/threat-model.md): eight trust boundaries, twelve findings, and the ranking those produce.

### Phase 13: Security baseline

**Status:** Complete

- Assess the platform against the GKE hardening guide, the MITRE ATT&CK container matrix, and CIS, with a tool rather than by reading.
- Run external checks that need no cluster access: TLS, response headers, DNS CAA, and DNSSEC.
- Run static checks over `terraform/` and `kubernetes/`, the published image, and the pinned Python dependencies.
- Read what Security Command Center already reports, which costs nothing and predates this phase.
- Verify the three account controls the threat model assumes rather than knows.
- Keep the scanners one-shot. A permanent in-cluster agent needs broad cluster read, which is a security decision of its own, and this node pool has no room for it.
- Reconcile every finding against the threat model, and drop the ones that do not apply to a platform with no data and one operator.
- Promote the external and static checks to a scheduled workflow, so the baseline is a control rather than a snapshot.

Kept thin deliberately: the ATT&CK mapping records the techniques that apply, with control and evidence, not a grid of mostly empty rows.

**Exit criteria met:** Every threat model finding is confirmed, closed, or reclassified against measured state. `scripts/check-public-surface.sh` runs daily in `security-scan.yml` and fails on a listed finding that regresses, proven by the deliberate-regression test recorded in the worklog. checkov runs on every pull request via `ci.yml`. kubescape ran one-shot against MITRE and NSA. Security Command Center was checked and found disabled, itself a finding. The three account controls (MFA, write access, branch protection) are all verified, and one was found broken: `k8-lab`'s branch ruleset existed but targeted no branch, fixed during this phase.

Not closed by this phase, carried to Phase 14: findings 2, 3, 4, 9 and 10, finding 6's CSP and `frame-ancestors`, and `sky`'s branch protection. Findings 3 and 9 were measured open rather than left unverified. The [threat model's findings table](reference/threat-model.md#findings) carries the status of all twelve.

Evidence: [Phase 13 worklog](worklog/phase-13-security-baseline.md)

Documentation: [hardening your GKE cluster](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster), [MITRE ATT&CK for Containers](https://attack.mitre.org/matrices/enterprise/containers/), [Security Command Center](https://cloud.google.com/security-command-center/docs/security-command-center-overview), [Kubescape](https://kubescape.io/docs/), [Trivy](https://trivy.dev/latest/docs/), [testssl.sh](https://testssl.sh/)

### Phase 14: Close the baseline

**Status:** In progress

Ordered by the threat model's ranking rather than by ease. The first item defends the only path an adversary is exercising today; the last is the one with six controls already on it.

Four bullets below shipped and were deployed during Phase 13: Cloud Armor rate limiting, the SSL policy, the response headers (except sky's CSP), and the pin-bump CI check. See the [Phase 13 worklog](worklog/phase-13-security-baseline.md).

- Add Cloud Armor rate limiting to the Gateway, sized from the Phase 12 measurements.
- Re-decide the federation trust boundary with its consequence written down, and record the outcome either way.
- Restrict certificate issuance with CAA records, and alert when the certificate leaves `ACTIVE`.
- Define an SSL policy with a TLS 1.2 floor and attach it to the Gateway.
- Add HSTS and the other response headers to every HTTPRoute rule serving the domain, and a Content Security Policy in `sky`, which is the only thing that knows what it loads.
- Refuse to propose a pin bump whose upstream CI is red.
- Add provenance, an SBOM, and signing to the build, and enforce them at admission.

One caution carried from the threat model: `includeSubDomains` and `preload` are one-way doors, so HSTS starts with a short `max-age`.

A second was overstated and is corrected here. Scoping federation to a ref does not cost the `workflow_dispatch` bootstrap path, because a dispatch from `main` resolves to `refs/heads/main`. What it costs is exercising delivery from a branch, and a branch rename breaking delivery until the condition follows it.

| Item | State |
| --- | --- |
| Rate limiting, SSL policy, response headers, pin-bump check | Shipped and deployed |
| Federation scoped to `refs/heads/main` | Applied. Allow path proven, deny path untested |
| Branch protection on both repositories | Done. `k8-lab` carries two mechanisms, consolidation open |
| Certificate renewal alerting | Done, as `cert-expiry` in the surface script rather than a Cloud Monitoring alert |
| Content Security Policy | Served on `/`. `/sky/` waits on a pin bump to deploy it |
| CAA records | Derived from the live issuer, not added. Blocked on whether the zone is Cloudflare-proxied |
| DNSSEC | Not decided |
| What the Security Command Center free tier covers | Not looked up. Phase 13 established only that it is disabled |
| Provenance, SBOM, signing, admission policy | Not started |
| Single-client flood | Not run. This is the exit criterion |

**Exit criteria:** The public endpoint survives a single-client flood without reaching the namespace quota. The TLS scan grades `A` or better. Every finding in the threat model is closed or carries a recorded acceptance.

Documentation: [Cloud Armor rate limiting](https://cloud.google.com/armor/docs/rate-limiting-overview), [SSL policies](https://cloud.google.com/load-balancing/docs/ssl-policies-concepts), [GKE Gateway configuration](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources), [CAA records](https://letsencrypt.org/docs/caa/), [Binary Authorization](https://cloud.google.com/binary-authorization/docs), [SLSA](https://slsa.dev/)

## Milestone 4: AI reference workload

Follows Milestone 3.

### Phase 15: Deterministic manifest review

- Add a small API for submitted Kubernetes YAML.
- Treat all submissions as untrusted input.
- Never execute submitted manifests.
- Run schema, security, and policy checks.
- Return reproducible findings with validator and policy versions.

**Exit criteria:** Known invalid manifests produce stable, testable findings without AI.

### Phase 16: AI explanation with closed validation

- Use Vertex AI only to explain findings and propose corrections.
- Authenticate from GKE with Workload Identity Federation.
- Revalidate every proposed manifest through the deterministic checks.
- Show a proposed manifest only when it passes revalidation.
- State clearly that submitted content is sent to a managed Google Cloud service.
- Limit request size, output tokens, rate, retries, and timeouts.

**Exit criteria:** AI suggestions cannot bypass the deterministic policy layer and no service account key is used.

Documentation: [authenticate GKE workloads](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity), [Vertex AI overview](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/overview), [Vertex AI pricing](https://cloud.google.com/vertex-ai/generative-ai/pricing)

## Later decision gates

These are not implementation commitments yet.

- Use Kustomize when environment or workload variants create real duplication.
- Compare Helm only when a reusable, parameterized workload package is needed.
- Compare Argo CD, Flux, and direct GitHub Actions when pull-based reconciliation or drift correction becomes necessary.
- Compare native policy controls, Kyverno, and Gatekeeper when policies exceed the native controls.
- Add Pub/Sub and workers only if synchronous review processing becomes a limitation.
- Add remote Terraform state before automated infrastructure apply or collaboration.
- Create a regional cluster temporarily for availability and recovery validation.
- Test sudden node loss and drain under load once autoscaling is in place.

Two gates closed into Milestone 3. Cloud Armor rate limiting was conditional on load testing showing that a single client can drive the namespace to its quota, and Phase 12 showed exactly that. Advanced supply-chain controls were conditional on the basic image pipeline being complete, and it is.

Documentation: [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/), [Cloud Storage Terraform state](https://cloud.google.com/docs/terraform/resource-management/store-state), [regional GKE clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters)

## Cost posture

- Use the available GCP credits to support hands-on validation.
- Keep the current zonal cluster available during active project work.
- Record costs and configure budget alerts. Measured at kr461.81 a week, fully covered by credits.
- Provision a regional cluster only when its availability behavior is being tested.
- Create the load generator VM and its VPC only for a test session, and delete both afterwards.
- Do not add GPU nodes unless self-hosted inference becomes a separate project goal.

## Immediate next step

Milestones 1 and 2 are closed. The platform is guarded, delivery is keyless, the workloads are public through Gateway API, rollouts drop no requests, and sky scales from two to eight replicas across nodes in three zones, with every claim above backed by evidence.

Milestone 3 is under way. [The threat model](reference/threat-model.md) ranks twelve findings, Phase 13 measured the platform against that frame rather than against a reading of it, and Phase 14 is closing what the measurement confirmed. What Phase 14 has not done is listed in its own entry above; the single-client flood is its exit criterion and has not been run. The AI reference workload follows in Milestone 4, on a platform whose security posture has been tested rather than described.

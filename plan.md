# Secure GKE Workload Platform Plan

## Goal

Build and prove a secure GKE workload delivery platform. The platform is the portfolio project. Once it is proven, agents operate it: triaging its security findings, reaching it through an audited path, and answering its alerts, held to the same evidence standard as the platform itself.

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

**Status:** Complete

Ordered by the threat model's ranking rather than by ease. The first item defends the only path an adversary is exercising today; the last is the one with six controls already on it.

Four bullets below shipped and were deployed during Phase 13: Cloud Armor rate limiting, the SSL policy, the response headers, and the pin-bump CI check. sky's own CSP followed later, when #106 moved the pin onto it. See the [Phase 13 worklog](worklog/phase-13-security-baseline.md).

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
| Federation scoped to `refs/heads/main` | Applied. Both directions proven |
| Branch protection on both repositories | Done. Consolidated onto `k8-lab`'s ruleset |
| Certificate renewal alerting | Done, as `cert-expiry` in the surface script rather than a Cloud Monitoring alert |
| Content Security Policy | Served on both paths |
| CAA records | Added and verified. Universal SSL disabled, because it was widening the set |
| DNSSEC | Signed 2026-09-18. DS published in `.com`, verified on two resolvers |
| Security Command Center | Premium activated at the organization level on 2026-09-18, on a free trial. One finding, which is its own onboarding. The first Security Health Analytics scan has not completed. What the tier becomes at trial end is not settled; [Phase 15](#phase-15-security-command-center-triage) carries the billing mode and treats Premium as a dependency |
| Provenance, SBOM, signing, admission policy | Deferred past Milestone 4, and accepted for now in the threat model |
| Single-client flood | Run twice on 2026-09-18. 593 of 1200 refused at 15 rps, and at 125 rps the throttle held sky to 3 of 8 replicas against 8 of 8 unthrottled. The exit criterion is met |

The last bullet is not done. Provenance, an SBOM, signing and admission enforcement are a phase of their own, and the threat model ranks the row they answer last, so it is [accepted for now](reference/threat-model.md#boundary-8-public-registries-to-the-running-image) rather than half started. It comes back after Milestone 5, with the next pass over the threat model, which Phase 16 requires anyway because giving an agent cluster credentials changes the model.

That acceptance was re-examined on 2026-09-20 against the two things Milestone 4 and Milestone 5 add: a second upstream repository, and an agent that can open a pull request here. It holds, and one adjacent control moves earlier instead. Both outcomes are recorded in [decisions.md](decisions.md#supply-chain-control-timing).

**Exit criteria:** The public endpoint survives a single-client flood without reaching the namespace quota. The TLS scan grades `A` or better. Every finding in the threat model is closed or carries a recorded acceptance. All three are met.

Documentation: [Cloud Armor rate limiting](https://cloud.google.com/armor/docs/rate-limiting-overview), [SSL policies](https://cloud.google.com/load-balancing/docs/ssl-policies-concepts), [GKE Gateway configuration](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources), [CAA records](https://letsencrypt.org/docs/caa/), [Binary Authorization](https://cloud.google.com/binary-authorization/docs), [SLSA](https://slsa.dev/)

## Milestone 4: Agent-operated security

Follows Milestone 3. The platform is proven, so the work moves to operating it. Security Command Center has produced findings continuously since 2026-09-18 and nobody reads them. That is the gap this milestone answers.

Every agent here reads. None can change the cluster. Write capability waits for Milestone 5, once the read path has been measured.

This milestone replaces a deterministic manifest reviewer. The reason is recorded in [decisions.md](decisions.md#ai-workload-direction).

Agent source lives in [ai-k8s](https://github.com/sindredg/ai-k8s), for the reason recorded in [decisions.md](decisions.md#agent-source-location). This repository holds the infrastructure, the identities and the evidence. Nothing below gives `ai-k8s` a Google Cloud credential: `k8-lab` builds it from a pinned commit, exactly as it builds `sky`.

**Terms.** Defined once here, then used plainly.

| Term | Meaning |
| --- | --- |
| Evidence corpus | The records an agent may cite: `.checkov.baseline`, the [threat model findings table](reference/threat-model.md#findings), `decisions.md`, and the agent's own `mapping.yaml` and `controls.yaml`. Compiled into the image at build time |
| Accepted and priced | A finding names something this repository already decided about and recorded the cost of. The verdict value is `accepted` |
| Write capability | Any path by which an agent changes state outside its own ledger. Phase 19 holds the only one, a pull request |

**Rules.** Two rules hold across every phase in this milestone.

1. The model classifies and explains. It owns no delivery semantics, no authorization, no persistence and no notification policy. Code outside the prompt enforces each of those.
2. Every operational string an agent reads is hostile input. Security Command Center finding bodies carry resource names chosen by whoever created the resource.

### Phase 15: Security Command Center triage

Built in three parts. The transport and the identity are applied and measured. The agent that reads them does not exist. Evidence for everything ticked is in [the worklog](worklog/phase-15-scc-triage.md).

**Dependency: Security Command Center Premium.** Event Threat Detection is a Premium detector. This phase triages the threat class alongside misconfiguration and external exposure, and it has already produced one threat finding: a drill Pod that Pod Security refused, which Event Threat Detection reported as a privileged container launch, and which the worker identity then pulled from the subscription. Standard drops that detector, and a class of this phase's input with it. Premium is a dependency of Phase 15, not a bonus on top of it.

The billing mode is a free trial, confirmed by the owner on 2026-09-20. There is no paid subscription and no consumption billing behind it, so Security Command Center costs nothing today and contributes nothing to the agent cost line while the trial runs. Phase 14 recorded that the tier falls back to Standard when the trial ends. That is an expectation rather than a measurement, and this phase depends on a Premium detector, so the tier is re-read at trial end rather than assumed either way.

#### Part 1: The transport

- [x] Export findings through a notification config onto Pub/Sub.
- [x] Give the subscription a dead letter topic, so a message nothing acknowledges is parked rather than cycling.
- [x] Create the verdict ledger bucket, versioned, with public access prevention enforced.
- [x] Prove a real finding crosses the path, and measure how long it takes. About two seconds.
- [x] Prove an unacknowledged message reaches the dead letter topic. Five attempts, body intact.

#### Part 2: The identity and the namespace

- [x] Give the agent a Google identity holding no key, scoped to one subscription rather than to the project.
- [x] Open the `agents` namespace with Pod Security `restricted`, a quota, a limit range and default-deny egress.
- [x] Prove Pod Security and the quota each reject a probe built to trip only that one.
- [x] Prove a Pod carrying the agent's ServiceAccount federates to the right Google identity, and that an otherwise identical Pod without the egress label cannot reach Google APIs.
- [x] Prove the grant is scoped to the verb: `:pull` is allowed, `get` on the same subscription is not.

**The permission boundary.** The worker consumes one subscription, creates records in one bucket, invokes one model, and writes its own log. Nothing else. Recorded in [decisions.md](decisions.md#agent-permission-boundary).

| Capability | Grant | Scoped to | State |
| --- | --- | --- | --- |
| Pull findings | `roles/pubsub.subscriber` | The `scc-triage` subscription, not the project | Applied and proven. `:pull` returns 200, `get` on the same subscription returns 403 |
| Write verdict records | `roles/storage.objectUser` | The verdict ledger bucket | Applied, and wider than the worker needs. The role also allows delete and overwrite |
| Invoke the model | `roles/aiplatform.user` | The project | Applied, and wider than the worker needs. A publisher model needs `aiplatform.endpoints.predict` alone |
| Notify | `roles/logging.logWriter` | The project | Applied. The role writes and cannot read any log |
| Federate | `roles/iam.workloadIdentityUser` | `agents/triage-worker` alone | Applied and proven. A Pod in that namespace receives `k8-lab-triage`, and the user-managed key list is empty |

Denied, and the denial is part of the design:

| Denied | Why it matters |
| --- | --- |
| Security Command Center API access | The worker reads findings from Pub/Sub. A read or a mute at the source would let a triage verdict silence its own input |
| Object deletion and overwrite in the ledger | The ledger is the replay source Phase 18 rebuilds from. A worker that can erase a record can erase the evidence that it ran |
| Any cluster credential | Phase 16 owns cluster reads. The worker holds no kubeconfig and no Kubernetes RBAC beyond its own ServiceAccount |
| Broad project roles | No `roles/editor`, no `roles/viewer`, no `*.admin`. `PRIMITIVE_ROLES_USED` is already a live finding against this project |

Two grants above are wider than the boundary the table describes, so they are open work:

- [ ] Replace `roles/aiplatform.user` with a custom role holding `aiplatform.endpoints.predict`, once an applied call path shows which permissions the call needs.
- [ ] Replace `roles/storage.objectUser` with create and read only, so the worker cannot delete or overwrite a ledger object.

Egress out of `agents` is also wider than intended. NetworkPolicy cannot match hostnames, so the rule admits everything outside the cluster on TCP 443 rather than the Google API range. It is recorded on [boundary 3](reference/threat-model.md#boundary-3-pod-to-cluster) and rated at the Phase 16 threat model pass.

#### Part 3: The agent

Lives in [ai-k8s](https://github.com/sindredg/ai-k8s), built by this repository from a pinned commit. Increment 1 calls no model, so the whole path is proven before a single token is spent.

**Before the first build:**

- [ ] Guard the `ai-k8s` pin with the same upstream check-run query that guards the `sky` pin, from the first bump rather than as a follow-up.
- [ ] Verify the pinned commit's signature and authorship before it is built. This is the one supply-chain control that moves earlier than the rest, for the reason recorded in [decisions.md](decisions.md#supply-chain-control-timing).

**The verdict contract.** Four values. Deterministic resolution runs before the model is called, and its outcome is a recorded field rather than a judgement the model makes.

| Verdict | Condition | Citations |
| --- | --- | --- |
| `accepted` | Resolution matched a corpus entry, and that entry prices this finding | One or more resolved corpus citations |
| `contradicts_decision` | Resolution matched, and the recorded decision does not hold for the resource the finding names | One or more resolved corpus citations |
| `new` | Resolution found no applicable entry, and the finding is complete enough to describe what it asserts | The source finding, plus `corpus_match: none` recorded explicitly |
| `insufficient_evidence` | The worker refused to rule | Optional. The record must list what evidence is missing |

An earlier rule said every verdict must cite a corpus entry. That rule is wrong and is corrected here. A genuinely new finding has nothing to cite, and the old rule pushed every real new risk into `insufficient_evidence`, where it reads as a worker fault rather than a platform one. The change is recorded in [decisions.md](decisions.md#triage-verdict-record).

The worker, not the model, separates the two unmatched verdicts:

- `new`: the finding parsed, every required field is present, the input fit the budget, and resolution returned no entry for the category and resource.
- `insufficient_evidence`: a required field is missing or unparseable, the input exceeded the token or tool budget, the model cited an entry that does not resolve, or the verdict needs a fact the corpus does not carry. The last case is real. The Event Threat Detection finding above asserts that a Pod was created, and nothing in the finding body says admission refused it.

Schema validation enforces that table. It rejects `accepted` or `contradicts_decision` with no resolved citation, rejects `new` when resolution returned a match, and rejects `insufficient_evidence` with an empty missing-evidence list. The model cannot drift the boundary over time, because it does not decide where the boundary is.

**The ledger state machine.** The key is the finding's canonical name, its event time and its state. The ledger holds one prefix per key, and each state below is a separate object written once under it. A finding's current state is the furthest state present.

| State | Written | On redelivery |
| --- | --- | --- |
| `received` | First, before anything else | The create fails. Read the prefix and resume from the furthest state present |
| `classified` | After the verdict validates, before any notification | Resume at `notification_attempted` |
| `notification_attempted` | Before the log entry that triggers the alert is emitted | Notify again. The state means a notification may or may not have gone out |
| `acknowledged` | After the Pub/Sub acknowledgement returns | Nothing to do. Drop the message |

Every write uses a create-only precondition, so the ledger is append-only and two workers on the same message produce one object rather than two. Duplicate email is accepted and a missed notification is not, which is what fixes the ordering. Both are recorded in [decisions.md](decisions.md#triage-idempotency).

**Increment 1, deterministic only:**

- [ ] Go module, one binary per deployable component.
- [ ] Compile the corpus at image build time rather than reading it at runtime. `corpusc` reads the corpus sources and emits one index.
- [ ] Give every corpus entry a typed, stable id: `checkov:<check>:<address>`, `threat:<n>`, `decision:<anchor>`, `control:<slug>`. A citation is one of these and nothing else. Resolution is an exact lookup.
- [ ] Fail the build, not the worker, on a malformed entry, an id collision, a mapping citing an id that does not exist, or a mapping without its justification.
- [ ] Write `mapping.yaml` by hand, one Security Command Center category to zero or more corpus entries. Each entry carries the concrete resource it was decided about and a line saying why the pairing holds. Name-based pairing produced two wrong matches while this phase was being drafted, so every entry is reviewed.
- [ ] Write `controls.yaml`, the controls this platform enforces, as citable facts pointing at the worklog that proved each one. Nothing else in the corpus asserts that a control held, which is what a threat finding needs.
- [ ] Resolve deterministically: category and resource both match, or it does not resolve. An accepted decision about one resource does not cover another resource of the same kind.
- [ ] Classify each finding against the verdict contract above.
- [ ] Emit verdicts against a versioned schema. Reject output that does not validate rather than reading meaning out of prose.
- [ ] Carry a digest of the finding body, so an attribute-only change is recorded as drift without a verdict.
- [ ] Implement the ledger state machine above, with a create-only precondition on every write.
- [ ] Set `resource.type` to `k8s_container` explicitly on every log entry. A client library reports `global`, the metric still counts it, and the alert never fires.
- [ ] Emit the verdict string in exactly the spelling `triage.tf` filters on. Any other spelling pages the platform owner.
- [ ] Run as one replica in `agents`, pulling continuously.
- [ ] Triage misconfiguration, external exposure and threat findings. Record the vulnerability volume and why it is out of scope rather than dropping it silently.
- [ ] Count how many findings the rules settled without a model. That number says whether the rules are doing their job.

**Increment 2, the model:**

- [ ] Call Vertex AI only for what deterministic matching could not settle.
- [ ] Resolve every citation the model returns against the baked-in corpus before accepting the verdict. A citation that does not resolve forces `insufficient_evidence`.
- [ ] Bound tokens and tool calls. Refuse rather than silently truncate when the input exceeds the budget.
- [ ] Record the model, its generation parameters, the prompt digest, the corpus commit, the agent commit and the image digest with every verdict, so a verdict can be reproduced.
- [ ] Emit the token count and the estimated cost of each run, on the verdict record and as a label on the log entry.
- [ ] Stop calling the model when a daily spend ceiling is reached, and record the refusal. A budget alert is not a limit, and credits make its thresholds misleading.
- [ ] Notify through the existing email channel rather than adding a second one.

**Exit criteria:**

Measurements:

- [ ] The overlap [Phase 14](worklog/phase-14-close-the-baseline.md) left open is measured with provenance: how many Security Health Analytics findings name something `.checkov.baseline` already prices. Three of seven by hand today, which is not the measurement.
- [ ] The count of findings the rules settled without a model is published alongside it.
- [ ] Security Command Center cost and Vertex AI cost are reported as separate lines, not as one agent cost. Security Command Center reads zero while the trial runs, and recording that is the point: it stops a free trial being mistaken for a cheap subscription.
- [ ] The tier is re-read when the trial ends, and the result is recorded. If it drops to Standard, Event Threat Detection goes with it and this phase triages one class fewer, which the plan states rather than the worker quietly seeing less.
- [ ] The idle agent fits on the existing two-node floor. The deployment records whether a third node appeared, and whether the agent caused it.

Failure paths, each proven by making it happen:

- [ ] Model output that does not validate against the schema is rejected, and the finding lands as `insufficient_evidence` rather than as a parsed guess.
- [ ] A Vertex AI timeout, and separately a permission failure, leave the message unacknowledged and the ledger record readable.
- [ ] A ledger write failure stops the worker before it notifies, and nothing is acknowledged.
- [ ] A redelivered Pub/Sub message produces one verdict, not two, proven by replaying a real delivery.
- [ ] Kill the worker after inference and before persistence. The finding is re-inferred and triaged once.
- [ ] Kill the worker after persistence and before notification. The finding is notified after the restart.
- [ ] Kill the worker after notification and before acknowledgement. The finding is notified again, and the ledger shows one `notification_attempted` record rather than two verdicts.
- [ ] An input larger than the token budget is refused with `insufficient_evidence` naming the budget, not truncated.
- [ ] Stop the agent while a finding is waiting. After the agent restarts, verify that it processes the finding successfully.
- [ ] A finding carrying an instruction is triaged to the same verdict as one without. Test every untrusted field the worker reads, not the resource name alone: category, resource name, description, external URI, source properties, and the finding's own severity. Use a real finding from a real detector.

### Phase 16: Cluster access through an audited gateway

- Hold the cluster credentials in one service, and expose reads as MCP tools.
- Expose tasks rather than verbs: `get_workload_health`, `get_recent_events`, `get_rollout_history`, `get_pod_logs`. A generic verb and resource allowlist still lets a caller compose a request nobody designed.
- Read the Kubernetes API and nothing else. Cloud Monitoring and Cloud Logging are a separate boundary, described in Phase 17.
- Expose no generic `kubectl`, no arbitrary API path, no caller-supplied label selector and no unbounded log read. Deny Secrets, `exec`, `attach`, `port-forward`, the proxy endpoints, and cluster-wide listing outright.
- Authenticate callers with audience-bound projected Kubernetes ServiceAccount tokens, validated by `TokenReview`. Workload Identity Federation authenticates a workload to Google APIs. It does not authenticate one Pod to another, and an earlier draft of this phase implied that it did. Recorded in [decisions.md](decisions.md#gateway-client-authentication).
- Let the gateway reach the Kubernetes API with its own projected ServiceAccount token, bound to a Role holding read verbs only.
- Authorize and log every call with the identity that made it. Phase 15 and Phase 17 get separate identities. Enforce authorization at the HTTP boundary and again inside every tool handler.
- Give no client its own kubeconfig, including the agents from Phase 15 and Phase 17.
- Bound request rate and response size. An agent reading the whole cluster is the cheap mistake here.
- Revisit the threat model. An agent holding cluster credentials is a trust boundary the current model does not have.

**Exit criteria:**

- [ ] A call outside the allowlist is refused and appears in the audit log, proven by making one.
- [ ] Test authorization at both layers independently. First, confirm that the HTTP boundary rejects a denied resource. Then bypass that boundary in a test and confirm that the tool handler also rejects it.
- [ ] A token minted for a different audience is rejected, and so is an expired one.
- [ ] The Phase 17 identity cannot call a tool scoped to Phase 15, and the reverse.
- [ ] A log read with no line or time bound is refused rather than served, and a response over the size bound is refused rather than truncated.
- [ ] No client holds a kubeconfig and no service account key exists, proven the way Phase 14 proved federation scoping.
- [ ] The threat model carries the new boundary, with its findings ranked alongside the existing twelve.

### Phase 17: First responder on alert

**The event path.** One path, stated rather than implied:

`Cloud Monitoring alert → Pub/Sub notification channel → deterministic context collector → MCP reads through the Phase 16 gateway → model diagnosis → the existing email channel`

The collector is code. It decides which alerts start a run, assembles the context, and enforces the budget. The model receives a prepared context and returns a diagnosis. Nothing reaches the model that the collector did not gather.

**Where observability data is read.** The responder reads Cloud Monitoring and Cloud Logging directly, with its own Google identity and read-only grants. It does not read them through the Phase 16 gateway, and that gateway does not grow Google Cloud tools. Recorded in [decisions.md](decisions.md#observability-read-boundary).

- Assemble context when an alert fires: recent events, the last rollout, Pod state, the metric that tripped, and the logs around it.
- Produce a first diagnosis before a human opens a terminal.
- Read cluster state only through the Phase 16 gateway.
- Scope the observability identity to reads: `roles/monitoring.viewer` for metrics, and `roles/logging.viewAccessor` on one log view rather than `roles/logging.viewer` on the project.
- Create that log view rather than reusing a built-in one. The project has two buckets today, `_Required` at 400 days and `_Default` at 30, and `_Default` carries only the stock `_AllLogs` and `_Default` views. Which logs the view admits is decided in Phase 17, once the responder's queries exist. That it is a dedicated view with its own grant is decided now.
- Turn on Data Access audit logs for Cloud Logging and Cloud Monitoring. They are off by default, so without them "every call is logged with the identity that made it" is not true of the responder's reads. They land in `_Default` at 30-day retention, which is the log volume this costs.
- Keep the responder out of its own audit trail. The stock `_Default` view excludes data access logs, so a view built on the same exclusion means the responder cannot read the log that records its reads.
- Replay the Phase 10 failure drills as a scored evaluation set, and widen it. Two drills cannot establish reliability. Add a healthy cluster where the answer is no action, missing telemetry, stale telemetry, an unrelated rollout running at the same time, an ambiguous root cause, a log line carrying an instruction, a context over budget, and a tool that times out.
- Score diagnosis accuracy, evidence grounding, false escalation, unsafe severity downgrade, abstention quality, latency, cost, and tool-policy violations. Abstention is a correct answer and is scored as one.
- Keep a holdout set. Rerun the whole set whenever the model, the prompt, the tools or the corpus changes.
- Bound cost per alert, and emit the token count and estimated cost of each run.

**Exit criteria:**

- [ ] The drill set is scored for time to a correct diagnosis, and the score is published including the drills the agent got wrong.
- [ ] A failed drill is recorded with its reason, in the same form as any other failure in this repository.
- [ ] A context over budget is refused with a stated reason rather than truncated.
- [ ] A tool timeout produces an abstention, not a diagnosis built on whatever arrived first.
- [ ] A log line carrying an instruction does not change the diagnosis.
- [ ] A log query outside the responder's log view is refused, proven by making one, and the refusal appears in the Data Access audit log.

Documentation: [Security Command Center notifications](https://cloud.google.com/security-command-center/docs/how-to-notifications), [Pub/Sub](https://cloud.google.com/pubsub/docs/overview), [authenticate GKE workloads](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity), [projected ServiceAccount tokens](https://kubernetes.io/docs/concepts/storage/projected-volumes/#serviceaccounttoken), [Model Context Protocol](https://modelcontextprotocol.io/), [log views](https://cloud.google.com/logging/docs/logs-views), [Data Access audit logs](https://cloud.google.com/logging/docs/audit/configure-data-access), [Vertex AI overview](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/overview), [Vertex AI pricing](https://cloud.google.com/vertex-ai/generative-ai/pricing)

## Milestone 5: The agent as a platform citizen

Follows Milestone 4. The agents stop standing beside the platform and become part of it. Their state becomes Kubernetes state, and their output goes through the same delivery chain as every other change.

### Phase 18: Findings as Kubernetes objects

**What is authoritative.** Phase 15 writes a Cloud Storage ledger and this phase adds a custom resource. Only one of them can be the source of truth, and it is the ledger.

| Component | Holds | Rebuilt from |
| --- | --- | --- |
| Cloud Storage ledger | Immutable evidence, one prefix per idempotency key, and the replay source | Nothing. It is the original |
| Finding custom resource | Current operational state, and the human-facing interface | The ledger, by replay |
| Controller | Nothing durable. It is a deterministic projection of ledger records onto custom resources | Not applicable |

One rule keeps this honest: the custom resource carries no field that cannot be re-derived from the ledger. If a human action is added later, such as an acknowledgement, it is written back to the ledger before it counts as state. Recorded in [decisions.md](decisions.md#finding-state-authority).

After a controller crash, state is rebuilt by replaying the ledger rather than by trusting what survived in etcd. A custom resource with no matching ledger record is an error, and the controller deletes it rather than reconciling it. The cluster alone cannot reconstruct a finding that exists only in the ledger, so a cluster rebuild is a replay and is timed as one.

- Define a custom resource for a finding and its triage verdict.
- Write a controller that projects ledger records onto those objects, with conditions on `status`.
- Make `kubectl get findings` the interface. etcd holds no finding state the ledger cannot rebuild.
- Move Phase 15's output onto the resource rather than into a notification that scrolls past.
- Version the resource from its first release. It is an interface others will read.
- Keep the object small: normalized finding metadata, the verdict, conditions, and digests or links to evidence. No prompt, no log body and no model transcript in etcd.
- Generate the manifest in [ai-k8s](https://github.com/sindredg/ai-k8s) from the controller's own types, and carry it here on the same pinned commit as the image. A hand-edited copy drifts from the types the controller compiles against.

**Exit criteria:**

- [ ] Findings from Phase 15 land as objects.
- [ ] Kill the controller mid-reconcile. It rebuilds from the ledger with no finding lost and none duplicated, recorded as a drill.
- [ ] Delete every custom resource and let the controller rebuild them. The result matches the ledger exactly.
- [ ] A custom resource with no ledger record is removed rather than reconciled.

### Phase 19: Remediation by pull request

The agent's only write capability is a pull request against this repository. It holds no cluster write access, through the Phase 16 gateway or otherwise.

**The human boundary is enforced, not claimed.** A human must merge every agent-created pull request, and the repository rules must be what stops the agent merging its own. Today `required_approving_review_count` is `0` on `Protect main`, so the merge is unguarded. The deferred gate between a required approval and a second identity is decided in favour of a required approval, recorded in [decisions.md](decisions.md#the-human-merge-boundary). The owner keeps ruleset bypass, because a single collaborator cannot approve their own pull requests. So the enforced property is that no automation identity can merge, which is narrower than every change being reviewed and is the property this phase needs.

What the GitHub App must and must not hold:

| Property | Required state |
| --- | --- |
| Permissions | `contents` and `pull requests`. Nothing for Actions, secrets, rulesets or repository administration |
| Credentials | Short-lived installation tokens. Never a personal access token |
| Ruleset bypass | Not a bypass actor. The bypass list is read back and holds the repository owner alone |
| Approval | Must not be able to approve. GitHub does not accept an approving review from a pull request's author, and the App is the author. Proven by attempting it |
| Merge | Cannot merge. Required checks plus one required approval block it, and the App cannot supply the approval |
| Cluster access | None. No Kubernetes RBAC, no gateway write tool, no kubeconfig |

**The initial scope of a proposed change.** Enforced by a required status check that reads the diff, because a limit the agent applies to itself is not a limit.

| Limit | Value |
| --- | --- |
| Allowed paths | `terraform/` and `kubernetes/` |
| Rejected outright | Workflow and repository configuration files, anything under `.github/`, binaries, symlinks, submodule entries, file mode changes, and any file outside the allowed paths |
| Rejected specifically | The evidence corpus: `.checkov.baseline`, `decisions.md` and `reference/threat-model.md`. The agent must not propose changes to the records its own verdicts cite |
| Size | One finding per pull request, at most 10 files and 200 changed lines |

Widening any row is a change to this table, and a human decision rather than a model decision.

- Authenticate the agent as a GitHub App on short-lived installation tokens.
- Let the existing controls gate it: required checks, checkov and kube-linter.
- Add the scope check above as a required check, and validate it outside the model prompt.
- Record every proposal and its outcome, including the rejected ones. The rejections are the evidence that the boundary holds.

**Exit criteria:**

- [ ] An agent-opened pull request is stopped by an existing status check, proven by watching it happen rather than by reasoning that it would.
- [ ] The agent attempts to merge its own pull request and fails, proven by attempting it and recording the refusal.
- [ ] The agent attempts to approve its own pull request and fails.
- [ ] A proposal touching a workflow file, and separately one over the size limit, is rejected by the scope check.
- [ ] The ruleset bypass list is read back and holds no automation identity.
- [ ] No agent identity holds a write verb on the cluster, proven the way Phase 14 proved federation scoping.

Documentation: [custom resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/), [the controller pattern](https://kubernetes.io/docs/concepts/architecture/controller/), [Kubebuilder](https://book.kubebuilder.io/), [API versioning](https://kubernetes.io/docs/reference/using-api/#api-versioning), [GitHub App installation tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation), [repository rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)

## Later decision gates

These are not implementation commitments yet.

- Use Kustomize when environment or workload variants create real duplication.
- Compare Helm only when a reusable, parameterized workload package is needed.
- Compare Argo CD, Flux, and direct GitHub Actions when pull-based reconciliation or drift correction becomes necessary.
- Compare native policy controls, Kyverno, and Gatekeeper when policies exceed the native controls.
- Add remote Terraform state before automated infrastructure apply or collaboration.
- Create a regional cluster temporarily for availability and recovery validation.
- Test sudden node loss and drain under load once autoscaling is in place.

Two gates closed into Milestone 3. Cloud Armor rate limiting was conditional on load testing showing that a single client can drive the namespace to its quota, and Phase 12 showed exactly that. Advanced supply-chain controls were conditional on the basic image pipeline being complete, and it is.

A third closes into Milestone 4, on a condition it was not written for. Pub/Sub and workers were gated on synchronous processing becoming a limitation, and no such limitation arrived. Security Command Center pushes findings continuously instead, with no synchronous request to attach them to, so Phase 15 commits to the gate for a different reason than the one recorded here.

Three of the [deferred decision records](decisions.md#deferred-decision-records) close with it, each on the condition it was written for. Vertex AI against self-hosted inference is decided in [decisions.md](decisions.md#inference-provider). A namespace per workload was gated on a third workload or a second owner arriving, and the triage worker is the third workload, decided in [decisions.md](decisions.md#agent-namespace). The choice between a required approval and a second identity, to stop the Phase 19 agent merging its own pull request, is decided in favour of a required approval in [decisions.md](decisions.md#the-human-merge-boundary).

Documentation: [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/), [Cloud Storage Terraform state](https://cloud.google.com/docs/terraform/resource-management/store-state), [regional GKE clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters)

## Cost posture

- Use the available GCP credits to support hands-on validation.
- Keep the current zonal cluster available during active project work.
- Record costs and configure budget alerts. Measured at kr461.81 a week, fully covered by credits.
- Provision a regional cluster only when its availability behavior is being tested.
- Create the load generator VM and its VPC only for a test session, and delete both afterwards.
- Do not add GPU nodes unless self-hosted inference becomes a separate project goal.

Four more apply to the agents, because their cost behaves differently from the platform's.

- Keep idle agent workloads inside the existing two-node floor. The node pool scales to three, so an agent that forces a third node is a cost the deployment has to justify. Record whether a third node appeared and whether the agent caused it.
- Report Security Command Center cost and Vertex AI inference cost as separate lines. They are one Google Cloud bill and two very different decisions.
- Emit the token count and the estimated cost of every model run, so cost is attributable to a finding rather than to a month.
- Enforce a spend ceiling in the agent itself. Credits cover the bill, so a billing budget threshold measures something other than what is being spent, and an alert that arrives after the spend is not a limit.

## Immediate next step

Milestones 1 and 2 are closed. The platform is guarded, delivery is keyless, the workloads are public through Gateway API, rollouts drop no requests, and sky scales from two to eight replicas across nodes in three zones, with every claim above backed by evidence.

Milestone 3 is closed. [The threat model](reference/threat-model.md) ranks twelve findings, Phase 13 measured the platform against that frame rather than against a reading of it, and Phase 14 closed eleven of them with evidence: federation scoped to a ref and both directions proven, both repositories protected under one mechanism, a Content Security Policy on both paths, CAA restricting issuance on a signed zone, and a rate limit measured under a flood at the rate Phase 12d used unthrottled. The twelfth, provenance and signing, is accepted for now with its reason recorded.

Phase 15 is under way, and Milestone 4 is not the milestone that used to be here. The deterministic manifest reviewer is retired, with the reason recorded in [decisions.md](decisions.md#ai-workload-direction): it needed nothing the cluster provides, and the measurement worth having was already written down. Phase 14 named the Security Command Center overlap as the comparison worth making and left it open, and Security Command Center has been producing findings since 2026-09-18 that nobody reads.

The transport is applied and measured. A finding change reaches the subscription in about two seconds, and a message nobody acknowledges is republished to a dead letter topic after five attempts with its body intact. The apply also produced its own first finding: `BUCKET_LOGGING_DISABLED` against the verdict ledger bucket, five seconds after Terraform created it, against a `CKV_GCP_62` already in `.checkov.baseline`. That is the overlap thesis on a resource created during the measurement, and it moves the hand count to three of seven.

The identity and the namespace are applied and proven too. A Pod in `agents` federates to `k8-lab-triage`, pulls a real finding, and is refused a `get` on the same subscription. Pod Security and the quota each reject a probe built to trip only that one.

What remains in Phase 15 is everything that reads. The worker in [ai-k8s](https://github.com/sindredg/ai-k8s) is empty, so no finding is triaged and no verdict has travelled the notification path the metric and alert policy already wait on. Every exit-criteria drill is open, and the overlap measurement still has no provenance. [Phase 15's worklog](worklog/phase-15-scc-triage.md) records what the transport changed about the contract: `gcloud` cannot reach Security Command Center v2, a finding carries three names and cannot be written back at the one it is read at, and `eventTime` tracks substance rather than scans, which is why the idempotency key holds.

The agents land on a platform whose security posture has been tested rather than described. All three in Milestone 4 read and none can change the cluster, so the threat model comes back in Phase 16, when an agent first holds cluster credentials.

Phases 16 to 19 were revised on 2026-09-20, before any of them started. Four things that were implied are now decided: how one Pod authenticates to another, where observability data is read, what is authoritative between the ledger and the custom resource, and what enforces the human merge boundary. The decisions are under [Agents](decisions.md#agents).

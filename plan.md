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

The first milestone takes the existing NGINX workload through validation, policy, image delivery, external access, observability, and failure testing.

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

**Status:** In progress. The private repository exists; the image does not.

- Turn the existing NGINX workload into a small project frontend.
- Build a non-root container image.
- Create Artifact Registry with Terraform.
- Scan the image and deploy it by immutable digest.
- Validate image pulls from the private node pool.

**Exit criteria:** The existing workload runs a project-owned image from Artifact Registry by digest.

Documentation: [Artifact Registry with GKE](https://cloud.google.com/artifact-registry/docs/integrate-gke), [Artifact Analysis](https://cloud.google.com/artifact-analysis/docs/container-scanning-overview), [GKE container security](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#container_security)

### Phase 6: Keyless application delivery

- Configure Workload Identity Federation for GitHub Actions.
- Use a dedicated, least-privilege pipeline identity.
- Restrict trust to the intended repository and deployment context.
- Build, push, deploy, wait for rollout, and run a smoke test.
- Stop the workflow when rollout validation fails.

**Exit criteria:** GitHub deploys the workload without a service account key and reports the rollout result.

Documentation: [Workload Identity Federation for deployment pipelines](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines), [pipeline service account practices](https://cloud.google.com/iam/docs/best-practices-for-using-service-accounts-in-deployment-pipelines)

### Phase 7: Gateway and HTTPS

- Enable GKE Gateway API.
- Create an external Gateway and HTTPRoute.
- Reserve a static IP.
- Add DNS and managed TLS after the domain decision.
- Keep workload Services private.

**Exit criteria:** The workload is reachable through the Gateway while its Service remains internal.

Documentation: [GKE Gateway API](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api), [deploy a Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways), [secure a Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway)

### Phase 8: Observability and evidence

- Create one workload health dashboard.
- Create one actionable availability alert.
- Trigger the alert deliberately and verify recovery.
- Measure onboarding and deployment time.
- Capture an actual GCP cost snapshot.
- Execute one failed rollout and rollback.
- Write one short incident postmortem.

**Exit criteria:** Every platform claim below has recorded commands, results, and evidence.

| Claim | Required evidence |
| --- | --- |
| Onboarding is repeatable | Time from configuration change to Ready workload |
| Quotas work | Excessive request attempted and rejected |
| Pod Security works | Privileged Pod attempted and rejected |
| Network isolation works | Unauthorized connection attempted and denied |
| Delivery is keyless | Successful pipeline run without stored cloud keys |
| Rollout is controlled | Failed version detected and previous version restored |
| Monitoring works | Deliberate failure triggered the expected alert |
| Cost is understood | Billing snapshot with the main cost sources identified |

Existing self-healing, scaling, restart, and rollback evidence counts toward this milestone.

Documentation: [GKE observability](https://cloud.google.com/kubernetes-engine/docs/concepts/observability), [Cloud Monitoring alerting](https://cloud.google.com/monitoring/alerts), [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)

## Milestone 2: AI reference workload

Start only after Milestone 1 is complete.

### Phase 9: Deterministic manifest review

- Add a small API for submitted Kubernetes YAML.
- Treat all submissions as untrusted input.
- Never execute submitted manifests.
- Run schema, security, and policy checks.
- Return reproducible findings with validator and policy versions.

**Exit criteria:** Known invalid manifests produce stable, testable findings without AI.

### Phase 10: AI explanation with closed validation

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
- Evaluate advanced supply-chain controls after the basic image pipeline is complete.

Documentation: [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/), [Cloud Storage Terraform state](https://cloud.google.com/docs/terraform/resource-management/store-state), [regional GKE clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters), [Binary Authorization](https://cloud.google.com/binary-authorization/docs)

## Cost posture

- Use the available GCP credits to support hands-on validation.
- Keep the current zonal cluster available during active project work.
- Record costs and configure budget alerts.
- Provision a regional cluster only when its availability behavior is being tested.
- Do not add GPU nodes unless self-hosted inference becomes a separate project goal.

## Immediate next step

Continue Phase 5. The registry exists, so the next slice builds a non-root image that listens on 8080, which then moves the container port through the Deployment and both NetworkPolicies and allows Pod Security to enforce `restricted`.

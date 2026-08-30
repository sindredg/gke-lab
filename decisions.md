# Architecture Decisions

Decisions are grouped by domain. Each entry records what was chosen, why, and what was rejected.

## Cluster

### Cluster operating mode

Decision: [GKE Standard](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode) with separately managed node pools.

Why: Provides direct control over nodes, scaling, networking, and upgrades.

Alternatives: [GKE Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview).

### Cluster availability

Decision: [Zonal cluster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/creating-a-zonal-cluster) in `europe-north1-a`.

Why: Keeps the initial topology and baseline resource usage small.

Alternatives: [Regional cluster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/creating-a-regional-cluster).

### Node pool

Decision: [One autoscaling general node pool](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/node-pools) with `e2-standard-2` nodes, 50 GB balanced disks, and a total size of one to three nodes.

Why: Provides predictable baseline capacity with room to scale.

Alternatives: [Other machine families](https://docs.cloud.google.com/compute/docs/machine-resource), [Spot VMs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/spot-vms), or [node auto-provisioning](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/node-auto-provisioning).

### Node security

Decision: [Shielded GKE Nodes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/shielded-gke-nodes) with a dedicated node service account.

Why: Hardens node boot integrity and avoids using the default Compute Engine identity.

Alternatives: [Default Compute Engine service account](https://docs.cloud.google.com/compute/docs/access/service-accounts#default_service_account).

### Upgrade policy

Decision: [Regular release channel](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels) with node auto-upgrade, auto-repair, and surge upgrades.

Why: Balances release freshness with stability and reduces upgrade disruption.

Alternatives: [Rapid, Stable, or Extended channels](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels).

## Networking

### VPC and IP allocation

Decision: [VPC-native cluster](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/alias-ips) with a custom VPC, `10.10.0.0/20` for nodes, and `10.20.0.0/16` for Pods.

Why: Provides explicit, routable, and non-overlapping address allocation.

Alternatives: [GKE-managed secondary ranges](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/alias-ips) or [Shared VPC](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cluster-shared-vpc-network).

### Service addresses

Decision: [GKE-managed Service range](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/alias-ips).

Why: Avoids reserving an additional subnet secondary range.

Alternatives: [User-managed Service secondary range](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/alias-ips).

### Node isolation and egress

Decision: [Private nodes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation) with [Cloud NAT](https://docs.cloud.google.com/nat/docs/gke-example).

Why: Removes public node IPs while preserving controlled outbound access.

Alternatives: [Public nodes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation) or [private nodes without general internet egress](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation).

### Control plane access

Decision: [DNS-based endpoint](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/network-isolation) with direct IP endpoints disabled.

Why: Uses IAM-controlled access without exposing a control plane IP endpoint.

Alternatives: [IP endpoints with authorized networks](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation).

### Cluster networking

Decision: [GKE Dataplane V2](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/dataplane-v2).

Why: Provides Cilium-based networking and built-in NetworkPolicy enforcement.

Alternatives: [Calico network policy](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/network-policy).

## Identity and access

### Workload identity

Decision: [Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity).

Why: Gives workloads short-lived identities without service account keys.

Alternatives: [Service account impersonation](https://docs.cloud.google.com/iam/docs/service-account-impersonation) or [service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete).

### Workload service account

Decision: A dedicated Kubernetes ServiceAccount for each workload, with [automountServiceAccountToken](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) disabled.

Why: The namespace default account is shared by every Pod, so any permission granted to it is granted to all of them. NGINX never calls the Kubernetes API, so a mounted token is only attack surface. Workload Identity Federation binds to a named account in Phase 6.

Alternatives: [The namespace default ServiceAccount](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/).

## Workload security

### Pod Security Standards

Decision: [Enforce the baseline standard](https://kubernetes.io/docs/concepts/security/pod-security-admission/) on the `demo` namespace, with `warn` and `audit` set to `restricted`, and all three pinned to `v1.35`.

Why: Baseline blocks the known privilege escalation routes today. Restricted cannot be enforced while the workload runs as root, so it reports instead of blocking and becomes the enforced level once Phase 5 delivers a non-root image. Pinning the version stops a cluster upgrade from changing enforcement without a repository change.

Alternatives: [Enforce restricted immediately](https://kubernetes.io/docs/concepts/security/pod-security-standards/), leave the namespace unlabelled, or add an external policy engine.

### Namespace network isolation

Decision: [Deny all Pod traffic in the `demo` namespace by default](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-ingress-and-all-egress-traffic), then allow cluster DNS for every Pod and HTTP to the NGINX Pods from Pods labelled `nginx-client`.

Why: A namespace with no policy lets any Pod in the cluster reach the workload and lets the workload reach anything, including the internet through Cloud NAT. Denying first makes every allowed path a reviewable line in this repository, and a Pod added later is isolated on creation rather than after someone remembers to write a policy for it. Both ends of the application path are declared because the dataplane checks the sender's egress and the receiver's ingress separately.

Alternatives: Leave the namespace open and rely on Pod Security alone, allow all egress and restrict only ingress, or select clients by namespace instead of by Pod label.

Enforcement comes from [GKE Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2), already enabled through `datapath_provider = "ADVANCED_DATAPATH"`. The legacy `network_policy` block is deliberately absent because Dataplane V2 enforces policy itself.

The DNS rule allows both `kube-dns` and `node-local-dns` Pods. [NodeLocal DNSCache](https://cloud.google.com/kubernetes-engine/docs/how-to/nodelocal-dns-cache) answers on the kube-dns cluster IP but runs as its own Pod with the label `k8s-app: node-local-dns`, so a rule naming only `kube-dns` selects a Pod that never receives the query. Allowing both keeps the rule correct whether or not the cache is present.

The rule cannot name the kube-dns Service address instead. Dataplane V2 rewrites a Service IP to a backend Pod before policy is evaluated, so an `ipBlock` naming that address matches nothing. NetworkPolicy selects Pods, never Services.

## Infrastructure and configuration

### Terraform structure

Decision: [Root configuration](https://docs.cloud.google.com/docs/terraform/best-practices/root-modules) composed from local `network` and `gke` modules.

Why: Keeps resource ownership clear while preserving reusable boundaries.

Alternatives: [Google GKE Terraform modules](https://docs.cloud.google.com/kubernetes-engine/docs/terraform).

### Terraform state and automation

Decision: [Local Terraform state](https://developer.hashicorp.com/terraform/language/state) and manual plan review for the current single-operator workflow.

Why: Keeps supporting infrastructure small while the platform is being established.

Alternatives: [Cloud Storage remote state](https://docs.cloud.google.com/docs/terraform/resource-management/store-state) and [Workload Identity Federation for deployment pipelines](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).

### Infrastructure and workload ownership

Decision: Terraform manages Google Cloud infrastructure. Declarative Kubernetes configuration manages in-cluster resources outside the GKE foundation state.

Why: Keeps cluster lifecycle separate from workload lifecycle and avoids coupling Kubernetes provider access to cluster creation or destruction.

Alternatives: [Terraform Kubernetes provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs), [Config Connector](https://cloud.google.com/config-connector/docs/overview), or a shared Terraform state.

### Kubernetes configuration management

Decision: Continue with plain Kubernetes YAML for the current workload. Adopt [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) when environment or workload variants create duplication.

Why: Preserves direct Kubernetes learning and avoids adding templates before there is a real variation to manage.

Alternatives: [Helm](https://helm.sh/docs/), Kustomize immediately, or Terraform-managed Kubernetes resources.

## Delivery

### Pipeline sequence

Decision: Add credential-free pull request validation first. Add keyless GitHub Actions delivery through [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines) after Artifact Registry and the custom image exist.

Why: Static validation needs no cloud access. Authentication is introduced only when the workflow must push or deploy.

Alternatives: Add cloud credentials to the first CI workflow or install a GitOps controller before the first delivery slice.

### Pull request validation scope

Decision: Validate Terraform formatting and configuration, and validate Kubernetes manifests against the upstream schemas with [kubeconform](https://github.com/yannh/kubeconform). Defer YAML and Markdown linting.

Why: The included checks catch configuration that would fail against a real cluster or provider. The deferred checks only enforce formatting and would have required repository-wide cleanup before the first workflow could pass.

Alternatives: Lint everything from the start, or run no validation until delivery is automated.

### Pipeline credentials

Decision: Grant the workflow `contents: read` only. Do not grant `id-token: write` or any Google Cloud identity.

Why: The absence of a token-minting permission is what makes the workflow verifiably unable to reach the project.

Alternatives: Attach a deployment identity to the validation workflow.

### Action pinning

Decision: Pin third-party GitHub Actions to a commit SHA with the version in a trailing comment. Pin validator releases to an exact version.

Why: A tag can be moved to different code after review. A commit SHA cannot.

Alternatives: [Pin by tag](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions) and accept the mutable reference.

### Kubernetes security linting

Decision: Run [kube-linter](https://docs.kubelinter.io/) in advisory mode and publish its findings to the run summary. Make it blocking once Phase 4 and Phase 5 close the findings it reports.

Why: Its three current findings need a non-root image and a scheduling decision, which are later phases. A check that cannot pass yet would either block all work or be ignored.

Alternatives: Enforce the default checks immediately, or configure a reduced check set and enforce that.

Risk: An advisory check proves nothing on its own. Phase 4 closes this by making it blocking.

### Merge protection

Decision: Require a pull request and both status checks on `main` through a repository ruleset, with no bypass actors.

Why: Validation that can be pushed past is documentation, not enforcement.

Alternatives: Advisory checks only, or an admin bypass for the repository owner.

### Initial delivery model

Decision: Use GitHub Actions for the first application deployment. Evaluate Argo CD and Flux when pull-based reconciliation, drift correction, or multiple environments create a requirement.

Why: One cluster and one workload do not yet justify another continuously running controller and recovery surface.

Alternatives: [Argo CD](https://argo-cd.readthedocs.io/en/stable/), [Flux](https://fluxcd.io/flux/), or manual deployment.

## Project and process

### Project focus

Decision: Build a secure GKE workload delivery platform, with an AI-assisted manifest reviewer as a later reference workload.

Why: Keeps cloud and Kubernetes engineering as the primary work while providing a concrete workload to prove the platform.

Alternatives: Build an [application-first AI service](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/overview) or a dedicated self-hosted AI platform.

### First platform milestone

Decision: Extend the existing NGINX workload into one complete vertical slice before adding the AI workload or broader platform features.

Why: Reuses the deployed cluster, manifests, validation, and evidence while keeping the first milestone complete and testable.

Alternatives: Implement networking, policy, delivery, observability, and AI as separate horizontal workstreams.

### Evidence requirement

Decision: A capability is complete only after its success path, relevant failure path, and recovery are recorded.

Why: Demonstrates that the platform works rather than only showing that resources exist.

Alternatives: Treat deployment completion or configuration review as sufficient evidence.

### Cost posture

Decision: Use the available GCP credits for hands-on testing, keep the zonal cluster available during active work, and provision regional capacity only for targeted validation.

Why: Prioritizes learning and evidence while still measuring actual costs and avoiding unnecessary GPU or regional runtime.

Alternatives: Destroy the cluster after every session or keep a regional production cluster running throughout development.

### Deferred decision records

Create short entries when these decision gates are reached:

- Native controls versus Kyverno or Gatekeeper
- GitHub Actions versus Argo CD or Flux for continued delivery
- Standard GKE features versus fleet and multi-cluster components
- Vertex AI versus self-hosted inference

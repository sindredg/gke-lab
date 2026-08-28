# Architecture Decisions

## Cluster operating mode

Decision: [GKE Standard](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode) with separately managed node pools.

Why: Provides direct control over nodes, scaling, networking, and upgrades.

Alternatives: [GKE Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview).

## Cluster availability

Decision: [Zonal cluster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/creating-a-zonal-cluster) in `europe-north1-a`.

Why: Keeps the initial topology and baseline resource usage small.

Alternatives: [Regional cluster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/creating-a-regional-cluster).

## VPC and IP allocation

Decision: [VPC-native cluster](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/alias-ips) with a custom VPC, `10.10.0.0/20` for nodes, and `10.20.0.0/16` for Pods.

Why: Provides explicit, routable, and non-overlapping address allocation.

Alternatives: [GKE-managed secondary ranges](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/alias-ips) or [Shared VPC](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cluster-shared-vpc-network).

## Service addresses

Decision: [GKE-managed Service range](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/alias-ips).

Why: Avoids reserving an additional subnet secondary range.

Alternatives: [User-managed Service secondary range](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/alias-ips).

## Node isolation and egress

Decision: [Private nodes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation) with [Cloud NAT](https://docs.cloud.google.com/nat/docs/gke-example).

Why: Removes public node IPs while preserving controlled outbound access.

Alternatives: [Public nodes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation) or [private nodes without general internet egress](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation).

## Control plane access

Decision: [DNS-based endpoint](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/network-isolation) with direct IP endpoints disabled.

Why: Uses IAM-controlled access without exposing a control plane IP endpoint.

Alternatives: [IP endpoints with authorized networks](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation).

## Cluster networking

Decision: [GKE Dataplane V2](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/dataplane-v2).

Why: Provides Cilium-based networking and built-in NetworkPolicy enforcement.

Alternatives: [Calico network policy](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/network-policy).

## Workload identity

Decision: [Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity).

Why: Gives workloads short-lived identities without service account keys.

Alternatives: [Service account impersonation](https://docs.cloud.google.com/iam/docs/service-account-impersonation) or [service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete).

## Node pool

Decision: [One autoscaling general node pool](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/node-pools) with `e2-standard-2` nodes, 50 GB balanced disks, and a total size of one to three nodes.

Why: Provides predictable baseline capacity with room to scale.

Alternatives: [Other machine families](https://docs.cloud.google.com/compute/docs/machine-resource), [Spot VMs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/spot-vms), or [node auto-provisioning](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/node-auto-provisioning).

## Node security

Decision: [Shielded GKE Nodes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/shielded-gke-nodes) with a dedicated node service account.

Why: Hardens node boot integrity and avoids using the default Compute Engine identity.

Alternatives: [Default Compute Engine service account](https://docs.cloud.google.com/compute/docs/access/service-accounts#default_service_account).

## Upgrade policy

Decision: [Regular release channel](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels) with node auto-upgrade, auto-repair, and surge upgrades.

Why: Balances release freshness with stability and reduces upgrade disruption.

Alternatives: [Rapid, Stable, or Extended channels](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels).

## Terraform structure

Decision: [Root configuration](https://docs.cloud.google.com/docs/terraform/best-practices/root-modules) composed from local `network` and `gke` modules.

Why: Keeps resource ownership clear while preserving reusable boundaries.

Alternatives: [Google GKE Terraform modules](https://docs.cloud.google.com/kubernetes-engine/docs/terraform).

## Terraform state and automation

Decision: [Local Terraform state](https://developer.hashicorp.com/terraform/language/state) and manual plan review for the current single-operator workflow.

Why: Keeps supporting infrastructure small while the platform is being established.

Alternatives: [Cloud Storage remote state](https://docs.cloud.google.com/docs/terraform/resource-management/store-state) and [Workload Identity Federation for deployment pipelines](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).

## Project focus

Decision: Build a secure GKE workload delivery platform, with an AI-assisted manifest reviewer as a later reference workload.

Why: Keeps cloud and Kubernetes engineering as the primary work while providing a concrete workload to prove the platform.

Alternatives: Build an [application-first AI service](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/overview) or a dedicated self-hosted AI platform.

## First platform milestone

Decision: Extend the existing NGINX workload into one complete vertical slice before adding the AI workload or broader platform features.

Why: Reuses the deployed cluster, manifests, validation, and evidence while keeping the first milestone complete and testable.

Alternatives: Implement networking, policy, delivery, observability, and AI as separate horizontal workstreams.

## Infrastructure and workload ownership

Decision: Terraform manages Google Cloud infrastructure. Declarative Kubernetes configuration manages in-cluster resources outside the GKE foundation state.

Why: Keeps cluster lifecycle separate from workload lifecycle and avoids coupling Kubernetes provider access to cluster creation or destruction.

Alternatives: [Terraform Kubernetes provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs), [Config Connector](https://cloud.google.com/config-connector/docs/overview), or a shared Terraform state.

## Kubernetes configuration management

Decision: Continue with plain Kubernetes YAML for the current workload. Adopt [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) when environment or workload variants create duplication.

Why: Preserves direct Kubernetes learning and avoids adding templates before there is a real variation to manage.

Alternatives: [Helm](https://helm.sh/docs/), Kustomize immediately, or Terraform-managed Kubernetes resources.

## Pipeline sequence

Decision: Add credential-free pull request validation first. Add keyless GitHub Actions delivery through [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines) after Artifact Registry and the custom image exist.

Why: Static validation needs no cloud access. Authentication is introduced only when the workflow must push or deploy.

Alternatives: Add cloud credentials to the first CI workflow or install a GitOps controller before the first delivery slice.

## Initial delivery model

Decision: Use GitHub Actions for the first application deployment. Evaluate Argo CD and Flux when pull-based reconciliation, drift correction, or multiple environments create a requirement.

Why: One cluster and one workload do not yet justify another continuously running controller and recovery surface.

Alternatives: [Argo CD](https://argo-cd.readthedocs.io/en/stable/), [Flux](https://fluxcd.io/flux/), or manual deployment.

## Evidence requirement

Decision: A capability is complete only after its success path, relevant failure path, and recovery are recorded.

Why: Demonstrates that the platform works rather than only showing that resources exist.

Alternatives: Treat deployment completion or configuration review as sufficient evidence.

## Cost posture

Decision: Use the available GCP credits for hands-on testing, keep the zonal cluster available during active work, and provision regional capacity only for targeted validation.

Why: Prioritizes learning and evidence while still measuring actual costs and avoiding unnecessary GPU or regional runtime.

Alternatives: Destroy the cluster after every session or keep a regional production cluster running throughout development.

## Deferred decision records

Create short ADRs when these decision gates are reached:

- Native controls versus Kyverno or Gatekeeper
- GitHub Actions versus Argo CD or Flux for continued delivery
- Standard GKE features versus fleet and multi-cluster components
- Vertex AI versus self-hosted inference

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

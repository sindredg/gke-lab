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

Decision: [Enforce the restricted standard](https://kubernetes.io/docs/concepts/security/pod-security-admission/) on the `demo` namespace, with `warn` and `audit` at the same level, and all three pinned to `v1.35`.

Why: Restricted is the strongest of the three standards and rejects the workload the project no longer runs. Pinning the version stops a cluster upgrade from changing enforcement without a repository change.

Phase 4 enforced `baseline` because the workload ran as root and `restricted` would have rejected it. That constraint is gone: the Phase 5 image runs as UID 101 and declares the fields the standard requires, so the level was raised rather than left reporting indefinitely. A standard set to report and never enforced is a standard nobody obeys.

Alternatives: Remain on `baseline`, leave the namespace unlabelled, or add an external policy engine.

### Namespace network isolation

Decision: [Deny all Pod traffic in the `demo` namespace by default](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-ingress-and-all-egress-traffic), then allow cluster DNS for every Pod and HTTP to the NGINX Pods from Pods labelled `nginx-client`.

Why: A namespace with no policy lets any Pod in the cluster reach the workload and lets the workload reach anything, including the internet through Cloud NAT. Denying first makes every allowed path a reviewable line in this repository, and a Pod added later is isolated on creation rather than after someone remembers to write a policy for it. Both ends of the application path are declared because the dataplane checks the sender's egress and the receiver's ingress separately.

Alternatives: Leave the namespace open and rely on Pod Security alone, allow all egress and restrict only ingress, or select clients by namespace instead of by Pod label.

Enforcement comes from [GKE Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2), already enabled through `datapath_provider = "ADVANCED_DATAPATH"`. The legacy `network_policy` block is deliberately absent because Dataplane V2 enforces policy itself.

The DNS rule allows both `kube-dns` and `node-local-dns` Pods. [NodeLocal DNSCache](https://cloud.google.com/kubernetes-engine/docs/how-to/nodelocal-dns-cache) answers on the kube-dns cluster IP but runs as its own Pod with the label `k8s-app: node-local-dns`, so a rule naming only `kube-dns` selects a Pod that never receives the query. Allowing both keeps the rule correct whether or not the cache is present.

The rule cannot name the kube-dns Service address instead. Dataplane V2 rewrites a Service IP to a backend Pod before policy is evaluated, so an `ipBlock` naming that address matches nothing. NetworkPolicy selects Pods, never Services.

## Images and supply chain

### Image registry

Decision: Publish images to a regional [Artifact Registry](https://cloud.google.com/artifact-registry/docs/integrate-gke) repository in the cluster region, created by Terraform alongside the cluster.

Why: A project-owned repository removes the runtime dependency on Docker Hub and its rate limits, and puts the images under the same access control as the rest of the platform. Matching the cluster region keeps pulls off the cross-region path, which costs both latency on every node scale-up and egress charges.

Alternatives: Continue pulling public images at deploy time, use a multi-region repository, or use the deprecated Container Registry.

### Tag immutability

Decision: Set `immutable_tags` on the repository, and deploy by digest rather than by tag.

Why: A tag is a label that can be repointed, so the same manifest can deploy different bytes on different days. A digest is derived from the content and cannot. Immutable tags enforce at the registry what deploying by digest achieves at the manifest, so neither depends on discipline.

Cost: The repository rejects a push to a tag that already exists, which rules out a moving `latest`. Delivery has to tag each build uniquely, by commit SHA.

Alternatives: Rely on convention alone, or allow mutable tags and pin only in the manifest.

### Registry retention

Decision: Delete untagged images after seven days, and keep the ten most recent versions regardless.

Why: Rebuilding content that already exists orphans the previous image, which loses its tag but continues to occupy billable storage. Without a policy, storage grows without bound. The KEEP rule takes precedence over the DELETE rule, so recent images survive even while untagged.

Alternatives: Retain everything, or delete on a fixed schedule with no protection for recent images.

### Base image

Decision: Build on [`nginxinc/nginx-unprivileged`](https://github.com/nginx/docker-nginx-unprivileged) rather than reconfiguring the standard NGINX image to drop privileges.

Why: The image already runs as a non-root user and writes its cache, temporary files, and PID to paths that user owns. Converting the standard image means finding each of those paths and correcting it, and a miss produces a container that starts and then fails on the first request rather than at build time. The upstream image is maintained against the same NGINX releases, so the version stays pinned to the same line the workload already runs.

Alternatives: Reconfigure the standard NGINX image, or build from a distroless base with a different server.

### Listening port

Decision: Serve on port 8080 inside the container, and keep the Service on port 80.

Why: Binding a port below 1024 requires `CAP_NET_BIND_SERVICE`, and the `restricted` Pod Security standard requires dropping all capabilities. The two cannot both hold, so the container port moves. The Service keeps port 80 and reaches the container through the named port `http`, so nothing that calls the Service changes.

Cost: The NetworkPolicy rules name the container port, not the Service port, so both have to move with it. That coupling is deliberate and is why the policies name a port at all.

### Image reference in the manifest

Decision: Reference the image by digest rather than by tag, keeping the tag alongside it for readability.

Why: A digest is derived from the image content, so a manifest naming one deploys exactly those bytes for as long as it exists. A tag is a label the registry could in principle move, and reading a manifest tells you nothing about which build a tag pointed at on a given day.

Cost: A digest is unreadable, and nothing in the manifest says which commit produced it. The tag beside it carries that, and Phase 6 removes the manual step by having delivery write the digest.

Alternatives: Deploy by tag and rely on the repository's immutable tags, or deploy by tag and accept the ambiguity.

### Registry access for nodes

Decision: Grant `roles/artifactregistry.reader` to the node service account, scoped to this repository rather than to the project.

Why: Image pulls use the node identity. The kubelet fetches the image before the container exists, so Workload Identity is not available at that point and cannot be used for pulls. Scoping the binding to one repository keeps the nodes from reading every repository the project may later hold.

The binding is required rather than a precaution. [`roles/container.defaultNodeServiceAccount`](https://cloud.google.com/iam/docs/roles-permissions/container), already held by the node account, grants five permissions covering logging, monitoring, and autoscaling metrics, and none for Artifact Registry. Pulls fail without this binding. Guidance stating that nodes can pull without extra roles describes the Compute Engine default service account, which receives broad automatic grants; Phase 1 replaced that account with a dedicated one.

Alternatives: Grant the role at project level.

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

### Pipeline authentication

Decision: Authenticate GitHub Actions through [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines), and create no user-managed service account keys.

Why: A downloaded key is a permanent bearer credential. Anyone who reads it is the pipeline until someone notices and rotates it, and nothing in the key records where it was used. A federated token is minted per run, expires in minutes, and carries the repository, workflow, and ref that requested it.

Cost: Federation is harder to reason about than a key, and its failure modes are less obvious. The [troubleshooting log](troubleshooting.md#a-federated-token-exchange-fails-with-econnreset) records the first one encountered.

Alternatives: A service account key in a GitHub secret, or a self-hosted runner holding an attached identity.

### Federation trust boundary

Decision: Restrict the OIDC provider with an `attribute_condition` on `assertion.repository`, and bind impersonation to a `principalSet://` naming that same attribute.

Why: The provider trusts GitHub's issuer, and every repository on GitHub receives tokens from that issuer. Without a condition, a validly signed token from any repository is accepted, including one an attacker creates. The condition is what narrows "signed by GitHub" to "signed by GitHub, for this repository".

`principalSet` rather than `principal` binds every workflow in the repository rather than one exact subject. The branch and workflow will change over this project's life; the repository will not.

Alternatives: Scope trust to a branch or environment as well, which is stricter and breaks on every branch rename.

### Pipeline authorization

Decision: Grant the pipeline identity `roles/container.clusterViewer` at the project, and a namespaced Kubernetes `Role` in `demo` for everything it actually does.

Why: Google IAM decides whether the pipeline can reach the cluster; Kubernetes RBAC decides what it may do inside. Splitting them keeps the project-level grant to discovery only. The Role has no `create` or `delete` on Deployments, no access to Secrets, and no reach outside `demo`, and it is short enough that a reviewer can check it in seconds.

Cost: The Role must be applied by a human before the first run, because the pipeline cannot create its own permissions. That bootstrapping step is the property that stops the pipeline widening its own access.

Alternatives: `roles/container.developer`, which is one line of Terraform and grants read and write on every object in every cluster in the project.

### Delivery workflow separation

Decision: Deliver from a second workflow rather than adding credentials to `ci.yml`.

Why: The validation workflow's claim is that it holds `contents: read` and cannot reach the project at all. Adding `id-token: write` would erase that for every pull request, including ones from forks. The claim is worth more than one fewer file.

Alternatives: A single workflow with conditional steps, or a reusable workflow called by both.

### Image reference at deploy time

Decision: Have the pipeline set the Deployment's image to the digest it just built, rather than committing the digest back to the repository.

Why: One source of change and no commit loop. The workflow needs no write access to the repository.

Cost: The digest in `kubernetes/nginx/deployment.yml` no longer matches what runs. Git describes the workload's shape; the cluster holds the current version. A controller reconciling from git closes this, and the [deferred decision](#deferred-decision-records) on Argo CD and Flux is where that is settled.

Alternatives: Commit the digest back to `main`, or substitute a placeholder at deploy time.

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

# Architecture Decisions

Decisions are grouped by domain. Each entry records what was chosen, why, what it costs when the cost is not obvious, and what was rejected. Entries keep that order and stay short: the worklog carries the narrative, this file carries the choice.

## Cluster

### Cluster operating mode

Decision: [GKE Standard](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode) with separately managed node pools.

Why: Provides direct control over nodes, scaling, networking, and upgrades.

Alternatives: [GKE Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview).

### Cluster availability

Decision: [Zonal cluster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/creating-a-zonal-cluster) in `europe-north1-a`, with nodes allowed in all three zones of `europe-north1`.

Why: A zonal control plane keeps the topology and baseline cost small. Nodes in one zone did not: at 16:26 and 16:31 UTC on 2026-09-15 the autoscaler asked for a third `e2-standard-2`, Compute Engine answered `ZONE_RESOURCE_POOL_EXHAUSTED` both times, and four sky Pods stayed `Pending` while the HPA wanted eight. Listing every zone lets the autoscaler place a node wherever the machine type is available.

Cost: The control plane is still in one zone, so an outage of `europe-north1-a` still takes the API away, though running Pods keep serving. Traffic between nodes in different zones is billed.

Alternatives: [Regional cluster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/creating-a-regional-cluster), which replicates the control plane across zones as well. A second node pool on another machine family, which answers a shortage of one machine type but not of one zone.

### Node pool

Decision: [One autoscaling general node pool](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/node-pools) with `e2-standard-2` nodes, 50 GB balanced disks, and a total size of two to three nodes across the region's three zones.

Why: Provides predictable baseline capacity with room to scale. The floor is two rather than one so that an evicted Pod has somewhere to land, which is what makes a disruption budget pace a drain instead of blocking it.

Alternatives: [Other machine families](https://docs.cloud.google.com/compute/docs/machine-resource), [Spot VMs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/spot-vms), or [node auto-provisioning](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/node-auto-provisioning).

### Node security

Decision: [Shielded GKE Nodes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/shielded-gke-nodes) with a dedicated node service account.

Why: Hardens node boot integrity and avoids using the default Compute Engine identity.

Alternatives: [Default Compute Engine service account](https://docs.cloud.google.com/compute/docs/access/service-accounts#default_service_account).

### Upgrade policy

Decision: [Regular release channel](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels) with node auto-upgrade, auto-repair, and surge upgrades, inside a daily [maintenance window](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions) at 01:00 UTC.

Why: Balances release freshness with stability and reduces upgrade disruption. The window makes node replacement predictable rather than whenever the channel reaches the cluster, which matters because auto-upgrade and auto-repair evict Pods without asking.

Alternatives: [Rapid, Stable, or Extended channels](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels).

### Replica placement

Decision: Spread replicas across nodes with a `topologySpreadConstraints` rule set to `ScheduleAnyway`, paired with a [PodDisruptionBudget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) of `minAvailable: 1` on each workload.

Why: A required rule would leave the second replica `Pending` whenever the pool sits at its floor, turning a resilience measure into an outage. With `maxSkew: 1` across exactly two nodes, `DoNotSchedule` would also refuse to reschedule during a drain, because the surviving node would sit at skew 2. The preference keeps replicas apart during the node replacements the Regular channel performs underneath a running workload.

Both budgets set `unhealthyPodEvictionPolicy: AlwaysAllow`. The default refuses to evict a Pod while the budget is unmet, even one that is not Ready and serves nothing, so a crashlooping replica could hold the drain the budget exists to pace.

Cost: The budget had to wait for the node floor. On a pool that can scale to one node, `minAvailable` blocks the drain an automatic upgrade depends on, so the floor of two and the budgets shipped as one change.

Alternatives: Required anti-affinity, or accepting co-located replicas.

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

Why: The namespace default account is shared by every Pod, so any permission granted to it is granted to all of them. NGINX never calls the Kubernetes API, so a mounted token is only attack surface.

Alternatives: [The namespace default ServiceAccount](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/).

## Workload security

### Pod Security Standards

Decision: [Enforce the restricted standard](https://kubernetes.io/docs/concepts/security/pod-security-admission/) on the `demo` namespace, with `warn` and `audit` at the same level, and all three pinned to `v1.35`.

Why: Restricted is the strongest of the three standards and rejects the workload the project no longer runs. Pinning the version stops a cluster upgrade from changing enforcement without a repository change. A standard set to report and never enforced is a standard nobody obeys.

Cost: The level could only be raised once the image stopped running as root. Phase 4 enforced `baseline` for that reason; the Phase 5 image runs as UID 101 and declares the fields the standard requires.

Alternatives: Remain on `baseline`, leave the namespace unlabelled, or add an external policy engine.

### Read-only root filesystem

Decision: Run both workloads with `readOnlyRootFilesystem: true`, and give each only the writable paths its process needs as `emptyDir` volumes: `/tmp` for sky, and `/tmp` and `/etc/nginx/conf.d` for nginx.

Why: A process that cannot write to its own image cannot persist a change to it. The restricted standard does not require it, so it has to be declared. nginx's paths come from the image rather than from guessing: `nginx.conf` puts the PID and every temp path under `/tmp`, and the entrypoint renders the page's template into `conf.d` at startup.

Cost: The nginx entrypoint does not fail when `conf.d` is unwritable. It logs an error and starts nginx with no server block, which runs, reports healthy workers, and refuses every connection. The readiness probe is the only thing that catches that, which is one more reason the probe targets `/healthz` rather than being removed. The [worklog](worklog/notes/manifest-linting.md) records the local runs that found it.

Alternatives: Leave the root writable, which kube-linter flags. Point `NGINX_ENVSUBST_OUTPUT_DIR` under `/tmp` and change the `include` in `nginx.conf` to match, which saves one volume by editing the image's own configuration.

### Namespace network isolation

Decision: [Deny all Pod traffic in the `demo` namespace by default](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-ingress-and-all-egress-traffic), then allow cluster DNS for every Pod and HTTP to the NGINX Pods from Pods labelled `nginx-client`. Enforcement comes from [GKE Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2), already enabled through `datapath_provider = "ADVANCED_DATAPATH"`, so the legacy `network_policy` block is deliberately absent.

Why: A namespace with no policy lets any Pod in the cluster reach the workload and lets the workload reach anything, including the internet through Cloud NAT. Denying first makes every allowed path a reviewable line in this repository, and a Pod added later is isolated on creation rather than after someone remembers to write a policy for it. Both ends of the application path are declared because the dataplane checks the sender's egress and the receiver's ingress separately.

Cost: The rules have to name Pods exactly. The DNS rule allows both `kube-dns` and `node-local-dns`, because [NodeLocal DNSCache](https://cloud.google.com/kubernetes-engine/docs/how-to/nodelocal-dns-cache) answers on the kube-dns cluster IP but runs as its own Pod labelled `k8s-app: node-local-dns`, so a rule naming only `kube-dns` selects a Pod that never receives the query. Naming the kube-dns Service address instead does not work either: Dataplane V2 rewrites a Service IP to a backend Pod before policy is evaluated, so an `ipBlock` holding that address matches nothing.

Alternatives: Leave the namespace open and rely on Pod Security alone, allow all egress and restrict only ingress, or select clients by namespace instead of by Pod label.

### Namespace boundary between workloads

Decision: Run the second workload in the existing `demo` namespace rather than giving it one of its own.

Why: The namespace is the unit that carries Pod Security enforcement, the default-deny policies, and the resource budget, and all three already apply to any Pod admitted to `demo`. A second namespace would duplicate that scaffolding and add a `ReferenceGrant` so the Gateway could route across the boundary, which is a phase of work rather than a configuration change. Both workloads are owned by the same person and fail together anyway, so the shared blast radius is real but not yet meaningful.

Alternatives: A namespace per workload, which is what genuine multi-tenancy would require and what a third workload should trigger. Recorded as a [deferred decision](#deferred-decision-records).

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

Alternatives: Keep the container on port 80 and grant the capability back, which the enforced standard rejects.

### Image reference in the manifest

Decision: Reference the image by digest rather than by tag, keeping the tag alongside it for readability.

Why: A digest is derived from the image content, so a manifest naming one deploys exactly those bytes for as long as it exists. A tag is a label the registry could in principle move, and reading a manifest tells you nothing about which build a tag pointed at on a given day.

Cost: A digest is unreadable, and nothing in the manifest says which commit produced it. The tag beside it carries that, and delivery writes the digest so there is no manual step.

Alternatives: Deploy by tag and rely on the repository's immutable tags, or deploy by tag and accept the ambiguity.

### Registry access for nodes

Decision: Grant `roles/artifactregistry.reader` to the node service account, scoped to this repository rather than to the project.

Why: Image pulls use the node identity. The kubelet fetches the image before the container exists, so Workload Identity is not available at that point and cannot be used for pulls. Scoping the binding to one repository keeps the nodes from reading every repository the project may later hold.

Cost: The binding is required rather than a precaution, and it is easy to assume otherwise. [`roles/container.defaultNodeServiceAccount`](https://cloud.google.com/iam/docs/roles-permissions/container), already held by the node account, covers logging, monitoring, and autoscaling metrics and grants nothing for Artifact Registry, so pulls fail without it. Guidance stating that nodes can pull without extra roles describes the Compute Engine default service account, which receives broad automatic grants; Phase 1 replaced that account with a dedicated one.

Alternatives: Grant the role at project level.

### Pod identity reported by the page

Decision: Render the Pod name, namespace, Pod IP, node, uid and image digest into the page from the running container, rather than describing them in prose.

Why: The rest of the page makes claims a reader cannot check, and non-root and deployed-by-digest are the two most load-bearing. The uid is read with `id -u` rather than copied from the Pod spec, so it reports what the container is rather than what it was asked to be. The downward API supplies the Pod facts; the image digest cannot come from it, so the pipeline sets it in the same patch that sets the image, and the two cannot drift.

Cost: The page publishes internal names to the internet, which suits a lab whose purpose is to be inspected and would be wrong for a production service. The HTML is no longer static, `sub_filter` runs on every response, and `Cache-Control: no-store` keeps a reload landing on the other replica visible.

Alternatives: Serve the facts as a JSON endpoint, which keeps the page static and puts the evidence where nobody looks. State nothing, which is what a production service should do.

### Platform explained on the page

Decision: Explain the platform on the page with diagrams that animate, driven by CSS alone: one cluster map the reader switches between five scenarios, a delivery chain, and the controls a request crosses.

Why: The evidence for the claims here is in [plan.md](plan.md) and the worklogs, which is a lot of reading for someone deciding whether any of it is real. A map that shows a rollout surging one Pod, or a cordoned node handing its Pods to another zone, makes the same point in the time it takes to read a sentence. CSS rather than script is what keeps that feature free: Phase 14 closed a finding by adding a Content Security Policy with no `script-src`, and a page that animates without JavaScript leaves the header exactly as it was.

Cost: The scenarios are drawn from the manifests rather than read from the cluster, so a change to a replica count, a zone or a rate limit has to be made in the page as well, and the page can go stale without anything failing. Scenario switching needs `:has()`; a browser without it shows the steady scene and the tabs do nothing. The file grew from 17 KB to 42 KB, all inline, and `sub_filter` now runs over that much more of each response.

Alternatives: Read the live cluster through a small API, which would make the map true by construction, and would need a ServiceAccount with read on Pods and nodes, a policy that allows script, and node names and Pod IPs published to the internet. Draw the same thing as a static image, which costs nothing to keep correct and shows nothing happening.

### Application source for the second workload

Decision: Build the sky image here, from [sindredg/sky](https://github.com/sindredg/sky) at a commit pinned in `.github/sky-upstream.ref`, rather than vendoring its source or pulling its published image.

Why: Upstream published to Azure Container Registry, which this cluster has no credentials for and should not be given any, and since its own workflows were removed it publishes no image at all. Rebuilding from a pinned commit keeps the image project-owned, private, and digest-deployed like every other image here, while leaving the application's own repository authoritative. The pin is the review boundary: taking an upstream change is a one-line commit that CI and a rollout then have to accept.

Alternatives: Copy the source into this repository, which forks it and makes upstream fixes a manual port. Or grant this cluster cross-cloud pull credentials, which trades a supply-chain property for convenience.

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

### Manifest layout

Decision: Group manifests by what owns them: `kubernetes/platform/` for the objects that belong to the namespace as a whole, and one directory per workload.

Why: Everything started in `kubernetes/nginx/` because nginx was the only workload. By the time sky arrived, that directory held the Namespace, the LimitRange, the ResourceQuota, the pipeline's Role and RoleBinding, the Gateway, the HTTP to HTTPS redirect and the two shared NetworkPolicies, none of which are nginx's. A reader looking for the Gateway looked in the wrong place first, and `kubectl apply -f kubernetes/nginx/` quietly meant "apply the platform as well".

Cost: The commands in the phase 4 to 11 worklogs were written against the old paths and have been updated to the new ones, so they still run. The objects themselves are untouched, so nothing had to be reapplied, but `HTTPRoute/nginx-https-redirect` now sits in `platform/` under a name that still says nginx. Renaming it means deleting and recreating the route, which is a live change rather than a file move, so the name stays until there is a reason to take that.

Alternatives: One directory per workload with the platform objects duplicated into each, which makes the namespace ambiguous. Kustomize with a base and overlays, which is the [deferred decision](#deferred-decision-records) on real duplication and is not this.

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

Decision: Validate Terraform formatting and configuration, validate Kubernetes manifests against the upstream schemas with [kubeconform](https://github.com/yannh/kubeconform), resolve every documentation link, anchor and screenshot, and lint the shell scripts with [shellcheck](https://www.shellcheck.net/). Defer YAML and Markdown style linting.

Why: The included checks catch configuration that would fail against a real cluster or provider. The documentation checks were added later, once the worklogs and their 259 screenshots had become most of the repository: a renamed file, a heading reworded after something links to it, or a screenshot that was never committed all render as a broken page, and nothing else here notices. The check is a script rather than an action, so the same command runs locally and in CI. Style linting stays deferred, because it enforces formatting rather than catching a claim that is no longer true.

Cost: Every screenshot has to be referenced by a worklog or the check fails, which is a rule about housekeeping rather than about the platform. It is the rule that keeps the images directory from filling with the ones that were never used.

Alternatives: Lint everything from the start, or run no validation until delivery is automated. A hosted link checker, which also follows external URLs and fails on someone else's outage.

### Action updates

Decision: Dependabot proposes GitHub Action bumps weekly, as pull requests.

Why: Pinning to a commit SHA is what makes [action pinning](#action-pinning) meaningful, and it is also what stops an action ever moving. Without something proposing the bump, a pinned SHA is a frozen one and an upstream fix never arrives. A pull request keeps the merge as the review, which is the same shape as the [upstream pin](#upstream-pin-automation).

Cost: A pull request to read most weeks, often for nothing important. Dependabot rewrites the SHA and its trailing version comment together, so the comment cannot drift from the pin it annotates.

Alternatives: Bump by hand when something breaks, which is how a pinned action reaches end of life unnoticed. Pin by tag and let it float, which is what action pinning rejected.

### Pipeline credentials

Decision: Grant the validation workflow `contents: read` only. Do not grant `id-token: write` or any Google Cloud identity.

Why: The absence of a token-minting permission is what makes the workflow verifiably unable to reach the project.

Alternatives: Attach a deployment identity to the validation workflow.

### Action pinning

Decision: Pin third-party GitHub Actions to a commit SHA with the version in a trailing comment. Pin validator releases to an exact version.

Why: A tag can be moved to different code after review. A commit SHA cannot.

Alternatives: [Pin by tag](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions) and accept the mutable reference.

### Kubernetes security linting

Decision: Run [kube-linter](https://docs.kubelinter.io/) with its default checks as a blocking step in the `Kubernetes` job, excluding `no-anti-affinity` in `.kube-linter.yaml`.

Why: It started advisory in Phase 3, because its findings needed a non-root image and a scheduling decision that came later. The plan was to make it blocking once Phases 4 and 5 closed them. That did not happen until 2026-09-16, and by then it reported four findings nobody was required to read, two of them real. An advisory check proves nothing on its own. `no-anti-affinity` is excluded because it only recognises `podAntiAffinity`, and replicas here spread with `topologySpreadConstraints` for the reasons in [replica placement](#replica-placement).

Cost: A new manifest has to satisfy every default check or name the one it disagrees with. The exclusion applies to the whole repository, so a future workload that genuinely lacks any spreading would not be flagged. The [worklog](worklog/notes/manifest-linting.md) records each finding and the injected failures that prove the gate.

Alternatives: Stay advisory, which is what let the findings sit. Per-object `ignore-check.kube-linter.io` annotations instead of a config file, which scope the exclusion to one Deployment but put linter configuration into the live object.

### Merge protection

Decision: Require a pull request and the status checks on `main` through a repository ruleset, with no bypass actors. `sky` uses classic protection requiring its two test jobs.

Why: Validation that can be pushed past is documentation, not enforcement. `sky` is where production's pinned commit comes from, so it is governed too.

Cost: `k8-lab` briefly carried a ruleset and a classic rule with disjoint check lists, because Phase 14 read a `404` from the classic endpoint as no protection at all when the ruleset was already in force. Consolidated on 2026-09-18: `Static analysis` moved into ruleset 21742516, which now requires all four checks, and the classic rule was deleted.

`Public surface` is deliberately not required. It runs on two paths only, so requiring it would leave every pull request that touches neither one pending forever.

`enforce_admins` is off on both. With no required reviewer, turning it on locks the sole owner out of their own repositories.

Alternatives: Advisory checks only, or an admin bypass for the repository owner. Leaving both mechanisms in place, rejected because a required-check list split across two API surfaces gives whoever reads either one an incomplete answer.

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

Decision: Restrict the OIDC provider with an `attribute_condition` on `assertion.repository` and `assertion.ref`, and bind impersonation to a `principalSet://` naming the repository attribute.

Why: The provider trusts GitHub's issuer, and every repository on GitHub receives tokens from that issuer. Without a condition, a validly signed token from any repository is accepted, including one an attacker creates. The condition narrows "signed by GitHub" to "signed by GitHub, for this repository, on this branch".

Repository alone was the earlier decision, on the grounds that a branch changes over a project's life and a repository does not. That is true and it left a consequence unstated, which Phase 13's [threat model](reference/threat-model.md) recorded as finding 2: pushing a branch is enough to mint pipeline credentials, so required checks and pull request review do not govern the path to Google Cloud. Merge protection decides what reaches `main`, not what a branch push can do.

Cost: A branch rename breaks delivery until the condition follows it. Delivery can no longer be exercised from a branch, so `workflow_dispatch` runs from `main` only. The ref is enforced at the provider rather than in the binding, so the `principalSet` still authorizes every workflow in the repository once a token is through.

Alternatives: Repository only, which this replaces. Binding the `principalSet` to `attribute.ref` as well, which moves the same control into IAM and makes pool membership depend on the branch.

### Pipeline authorization

Decision: Grant the pipeline identity `roles/container.clusterViewer` at the project, and a namespaced Kubernetes `Role` in `demo` for everything it actually does.

Why: Google IAM decides whether the pipeline can reach the cluster; Kubernetes RBAC decides what it may do inside. Splitting them keeps the project-level grant to discovery only. The Role has no `create` or `delete` on Deployments, no access to Secrets, and no reach outside `demo`, and it is short enough that a reviewer can check it in seconds.

Cost: The Role must be applied by a human before the first run, because the pipeline cannot create its own permissions. That bootstrapping step is the property that stops the pipeline widening its own access.

Alternatives: `roles/container.developer`, which is one line of Terraform and grants read and write on every object in every cluster in the project.

### Delivery workflow separation

Decision: Deliver from a second workflow rather than adding credentials to `ci.yml`.

Why: The validation workflow's claim is that it holds `contents: read` and cannot reach the project at all. Adding `id-token: write` would erase that for every pull request, including ones from forks. The claim is worth more than one fewer file.

Alternatives: A single workflow with conditional steps, or a reusable workflow called by both.

### Shared smoke test

Decision: Keep `Deploy` and `Deploy sky` as separate workflows, but move the in-cluster smoke test into the `./.github/actions/smoke-test` composite action both call.

Why: The two workflows were 91% identical line for line, and the smoke step was the worst of it: 37 lines repeated byte for byte apart from the Pod name, the client label and the URL. Sixteen of those lines are the `securityContext` the restricted Pod Security standard requires, so the duplication was not only length. A change to what the standard demands had to be made twice, correctly, or the second workload's smoke Pod would be rejected at admission while the first still passed.

The workflows themselves stay separate. That is the [delivery workflow separation](#delivery-workflow-separation) decision and it is unchanged: what is shared here is one step, not the credential boundary.

Cost: The nginx smoke Pod is now named `smoke-nginx-<run id>` rather than `smoke-<run id>`, because the action derives the name from the Service. The Pod is created and deleted inside the step, so nothing outside it refers to the name. The action is also a second file to open when reading either pipeline.

Alternatives: A `workflow_call` reusable workflow covering the whole job, which would cut roughly three times as much but has to carry `build_only` and the upstream fetch as inputs, leaving a conditional shared workflow in place of two readable ones. Or leaving the duplication and relying on a reviewer to catch drift, which is what the repeated `securityContext` already argues against.

### Deployment update method

Decision: Render this run's digest into `deployment.yml` with `kubectl set image --local` and apply the result, instead of patching the live Deployment.

Why: A patch only ever changed the fields it named. Every other edit to `deployment.yml` merged to `main` and never reached the cluster, which is how a Deployment declaring five environment variables ran with one. Applying carries the image and the rest of the manifest in the same rollout, and an apply that changes nothing is a no-op. Both deploy workflows also trigger on their workload's manifest directory, so a change to `deployment.yml` alone rolls out on merge. Until 2026-09-16 the nginx workflow triggered on `app/**` only, and a manifest-only change waited for the next image change.

Cost: Only the Deployment is applied. The namespace, quotas, policies and routes stay manual, because letting the pipeline apply them means granting it authority over its own RBAC. A change to another file in `kubernetes/nginx/`, such as the Service, still triggers a full build and rollout that does not apply the file that changed.

Alternatives: Apply the whole directory, which needs a far broader Role. Keep patching and apply by hand, which is what failed.

### Image reference at deploy time

Decision: Have the pipeline set the Deployment's image to the digest it just built, rather than committing the digest back to the repository.

Why: One source of change and no commit loop. The workflow needs no write access to the repository.

Cost: The digest in `kubernetes/nginx/deployment.yml` no longer matches what runs. Git describes the workload's shape; the cluster holds the current version. A controller reconciling from git closes this, and the [deferred decision](#deferred-decision-records) on Argo CD and Flux is where that is settled.

Alternatives: Commit the digest back to `main`, or substitute a placeholder at deploy time.

### Upstream pin automation

Decision: A scheduled workflow, `Watch sky`, opens a pull request that moves the commit in `.github/sky-upstream.ref` to the head of [sindredg/sky](https://github.com/sindredg/sky). Merging it is the review.

Why: `deploy-sky.yml` fetches a commit rather than a branch, so what is built is what was reviewed and a re-run of an old run rebuilds the same source. Tracking `main` would remove the bump and that property together, and leaving the bump to be typed by hand lets the pin drift until someone remembers. Proposing it keeps the decision on a merge. The workflow fetches the commit during the run, so a pin that cannot resolve fails there rather than in a deploy.

Cost: The pin is a data file only because GitHub rejects a workflow-token push that touches `.github/workflows`, and no permission lifts it. The job holds `contents: write` and `pull-requests: write`, more than any other workflow here, which is what keeps the pin as data rather than as a credential. Two gaps remain open and are recorded in the [worklog](worklog/notes/upstream-pin-automation.md): the repository does not allow Actions to create pull requests, so every bump so far has been opened by hand from the link in the run's warning, and a pull request opened by the workflow token raises no workflow events, so `ci.yml` would not run on it before merge. Turning the setting on without closing the second would trade a manual click for a hole in [merge protection](#merge-protection).

Alternatives: Track `main` and rebuild on a schedule, which removes the review boundary. Hold a personal access token, which buys the workflow-file write and gives this repository the one long-lived credential it does not otherwise have. Dependabot or Renovate, neither of which tracks a bare commit in a data file.

## Ingress and TLS

### Ingress mechanism

Decision: Publish through a `Gateway` on `gke-l7-global-external-managed` rather than an Ingress object.

Why: Routing is expressed in the API rather than in annotations. A redirect, a hostname and a backend are typed fields, so the configuration says what it does and CI can check its shape. Gateway API is also where GKE's load balancer features are being added, and Ingress is where they are not.

Cost: The GKE extensions are proprietary CRDs. `HealthCheckPolicy` has no public schema, so `kubeconform` skips it with `-ignore-missing-schemas` and CI validates everything except the one file most likely to be wrong.

Alternatives: An Ingress with GKE annotations, which is better documented and worse to read.

### Load balancer backend target

Decision: Let the Gateway controller build a network endpoint group and leave the `nginx` Service `ClusterIP`.

Why: This is what allows both halves of the phase to hold at once. The load balancer reaches Pod IP and port pairs directly, and the Service is used only to work out which Pods belong in the group. Publishing the workload therefore changes the path into the cluster rather than the exposure of the Service.

Cost: The hop the load balancer makes is invisible to Kubernetes. A Pod is reachable from Google's proxies whether or not any Service would route to it, so Pod-level policy is the only thing standing between the internet and the container.

Alternatives: `LoadBalancer` or `NodePort`, both of which publish the Service itself and forfeit the claim.

### External address ownership

Decision: Reserve a global external address in Terraform and have the `Gateway` name it through `addresses.type: NamedAddress`.

Why: The address outlives any Gateway object using it. DNS points at a value Terraform owns, so deleting and recreating the Gateway does not change where the domain resolves, and the manifest carries a name rather than an IP.

Cost: One more resource, and a reserved address bills whether or not a load balancer is attached.

Alternatives: Let the controller allocate an ephemeral address, which changes on recreation and makes the DNS record a moving target.

### Certificate delivery

Decision: Attach certificates with the `networking.gke.io/certmap` annotation, pointing at a Certificate Manager map.

Why: Renewal is Google's problem and no key material is in the repository. The map is indirection that earns itself: one Gateway can serve several certificates chosen by hostname, and swapping a certificate is an entry change rather than a Gateway change.

Cost: Three resources where a Secret is one, and `hostname` on a map entry is immutable, so changing the name a certificate serves replaces the entry.

Alternatives: A TLS Secret listed in the listener, which puts renewal and private keys back on us.

### Domain validation method

Decision: Prove domain control with a DNS authorization.

Why: It decouples issuance from the cutover. A valid certificate can exist before the domain points anywhere, so the certificate is not blocked on DNS and DNS is not blocked on the certificate. Load balancer authorization checks the live load balancer at that name, which requires the cutover to have already happened.

Cost: One extra record, permanently, because renewal re-checks it.

Alternatives: Load balancer authorization, which needs no record and orders the work the wrong way round.

### DNS authorization record type

Decision: Issue the managed certificate against a `PER_PROJECT_RECORD` DNS authorization, validating at `_acme-challenge_<hash>.sindrg.com` rather than the default `_acme-challenge.sindrg.com`.

Why: Cloudflare serves its own hidden `TXT` records at `_acme-challenge` for Universal SSL. A name holding both a `CNAME` and a `TXT` answers `TXT` queries from the `TXT` set alone, so validation never followed the `CNAME` to Google and the certificate failed with `CONFIG` on every attempt. A per-project label is not contested by anything.

Cost: The challenge record's name is generated rather than predictable, so it cannot be written before the authorization exists. `type` is immutable, so changing it later replaces the authorization, the certificate and the map entry together.

Alternatives: Disable Cloudflare's Universal SSL, which removes the conflicting records but is console state rather than configuration and may be reprovisioned. Move DNS to Cloud DNS, which removes the conflict and the registrar's edge features with it.

The first alternative was taken later, for the reason in the next entry. `PER_PROJECT_RECORD` stays: it is configuration, and nothing contests it.

### Certificate issuance restriction

Decision: Publish `0 issue "pki.goog"` and `0 issuewild ";"` on `sindrg.com`, and disable Cloudflare's Universal SSL so that pair is the whole record.

Why: Certificate issuance is proved by a DNS record, so without CAA any CA will issue for this domain and none of the cluster's hardening is on that path. `pki.goog` is Google Trust Services' Issuer Domain Name, and GTS issues the live certificate. `issuewild ";"` is the second half rather than an extra: RFC 8659 falls back to `issue` for a wildcard request when no `issuewild` record exists, so `issue "pki.goog"` alone would still authorise a wildcard this platform never issues.

Universal SSL is why the pair needs a second decision. With it on, Cloudflare adds CAA records for its own partner CAs to any zone that has one, shows none of them in its dashboard, and documents the list as [not exhaustive](https://developers.cloudflare.com/ssl/edge-certificates/caa-records/). Phase 14 measured eleven records where the zone held two, and because RFC 8659 takes the union at a name, the injected `issuewild` entries re-authorised the wildcard issuance the pair exists to forbid.

Cost: Universal SSL is console state rather than configuration, so nothing here prevents it being switched back on, and `scripts/check-public-surface.sh` reads CAA for presence rather than contents. Changing CA means editing the zone by hand first, and a wrong record fails at renewal rather than at request time.

Alternatives: `issue "pki.goog"` alone, which leaves wildcard issuance authorised. Flags `128`, which adds nothing for tags every compliant CA understands. Leaving Universal SSL on, rejected because the partner set is undisclosed and Cloudflare's to change. Moving the zone to Cloud DNS, which would put the record in Terraform; out of scope because DNS is not this repository's to move.

### Zone signing

Decision: Sign `sindrg.com` with DNSSEC through Cloudflare, which is both the DNS host and the registrar, so it publishes the DS in `.com` itself.

Why: Certificate issuance is proved by a DNS answer, and so is the CAA record that restricts issuance to `pki.goog`. Unsigned, both are unauthenticated, which is the compounding the [threat model](reference/threat-model.md#boundary-6-dns-and-certificate-issuance) ranks second. Signing authenticates the answers the platform depends on. The alternative was to accept it in writing, and finding 9 closes either way, because its proposed response was Decide.

Cost: A key rollover this project now owns, and a second way to break resolution. A DS in `.com` that names a key the zone no longer uses makes every validating resolver return `SERVFAIL` for the whole domain, while resolvers that do not validate keep working, so the outage is invisible from wherever you happen to be testing. Cloudflare manages the rollover while it holds both halves, and the risk arrives the day DNS or the registration moves. Like Universal SSL, this is console state rather than configuration: nothing in `terraform/` enforces it.

Alternatives: Accept the zone unsigned, recording that its answers are forgeable by anyone who can intercept them. Rejected because the CAA record closed in the same phase rests on those answers. Sign while keeping the registration elsewhere, which means carrying the DS by hand and owning the rollover directly.

### Redirect to HTTPS

Decision: Answer plain HTTP with a `301` from a second `HTTPRoute` attached to the HTTP listener, rather than redirecting in NGINX.

Why: No request reaches a Pod in clear text. Google answers on port 80 and the container never sees an unencrypted request, so the redirect cannot be lost by changing the image or its configuration.

Cost: Two routes and a listener kept open only to redirect. The main route binds to `sectionName: https`, so it cannot attach until the HTTPS listener exists.

Alternatives: Redirect inside NGINX, which lets clear-text requests into the Pod, or close port 80, which breaks anyone typing the bare domain.

### Load balancer health checks

Decision: Point the load balancer's health check at `/healthz` on port 8080 through a `HealthCheckPolicy`, mirroring the Kubernetes probes.

Why: The default check fetches `/`, so the backend's health becomes a property of the page's content. A dedicated endpoint keeps the check about whether the server is serving.

Cost: A GKE-proprietary CRD with no public schema, so CI cannot validate it. A wrong field here surfaces as unhealthy backends rather than a failed apply.

Alternatives: Accept the default check on `/`, which passes for the wrong reasons and fails for them too.

### Health check source range

Decision: Allow ingress to the Pods from `130.211.0.0/22` and `35.191.0.0/16` with an `ipBlock`.

Why: The default-deny policy drops the health checks, and no `podSelector` can express the source, because Google's proxies are not Pods and hold no identity in the cluster. An address range is the only form the API can state.

Cost: The coarsest control that works. Every Google Cloud customer's proxies originate in those ranges, so this admits a network location rather than a caller.

Alternatives: None within NetworkPolicy. Filtering by caller belongs to Cloud Armor, which is a phase of its own.

### Second workload routing

Decision: Serve the sky workload at `/sky` on the existing hostname, routing `/sky` with its prefix rewritten away and routing `/api` and `/static` to it unchanged. The load balancer reaches `/health` through the `HealthCheckPolicy` rather than through a route.

Why: The application is not prefix aware. Its page asks for `/static/app.js` and its script fetches `/api/places`, both absolute, so the prefix cannot be confined to `/sky` without changing the application. Gateway API matches the longest prefix first, so these rules take precedence over the project page's `/` without either route referring to the other.

Cost: Rewriting a prefix away exposes everything behind it, so `/sky/health` and `/sky/version` are both public. `/sky/version` returns the upstream commit the image was built from, which is a fact about a public repository rather than a secret, but it is a consequence of the rewrite worth stating rather than discovering.

Alternatives: A `sky.` subdomain, which keeps each workload's path namespace whole at the cost of a DNS record and a certificate map entry, and remains the answer if a second application ever wants `/api`. Or patch a vendored copy to be prefix-clean, which forks the application to solve a routing problem.

### Edge rate limiting

Decision: Throttle a single address to 300 requests a minute with Cloud Armor, attached to each backend by a `GCPBackendPolicy`, and enable no preconfigured WAF rules.

Why: Phase 12 measured one client driving the namespace into its quota, which stalled the autoscaler at five Pods of eight and failed a deploy during the stall. This is the top ranked path in the [threat model](reference/threat-model.md) because it is the one an adversary exercises without effort. The threshold is 5 requests a second, an eighth of what two replicas serve at saturation and well above what reading the site generates. `throttle` rejects the excess rather than banning the address, which is the recoverable choice for a false positive.

Cost: A misjudged threshold rejects real visitors, and the uptime check counts against it at three requests a minute. `preview` on the rule turns enforcement into logging if the threshold needs observing first. Phase 14 measured two more. The policy is attached per backend service, so one address gets 300 a minute on nginx and another 300 on sky rather than 300 across the site. And the throttle caps scale-out without preventing it: at 125 rps from one address sky still scaled from two replicas to three, well inside the quota but not at rest.

Alternatives: The preconfigured WAF rules, including the Log4Shell signature `CKV_GCP_73` asks for. Nothing in this estate runs a JVM, and the application has no database, no authentication and no input beyond bounded query parameters, so the OWASP signatures defend nothing here while adding a false positive surface. Adding them would be hardening by category rather than against an adversary, which is what the threat model exists to avoid. The finding is recorded in `.checkov.baseline` rather than skipped, so the acceptance stays visible.

## Observability

### Telemetry scope

Decision: Declare `SYSTEM_COMPONENTS` and `WORKLOADS` logging and `SYSTEM_COMPONENTS` monitoring with Managed Service for Prometheus, and leave `API_SERVER`, `SCHEDULER`, and `CONTROLLER_MANAGER` off. The `CADVISOR`, `HPA`, `DEPLOYMENT` and `POD` packages are recorded under [Scaling telemetry](#scaling-telemetry).

Why: Container stdout is the largest ingest line on a cluster this size and Cloud Logging bills it, so keeping `WORKLOADS` is a cost decision rather than a free one. The control plane streams answer "who changed this object", and are noisy and billable for everything else. Writing the scope down also turned an inherited default into a recorded choice, which the first plan proved by proposing a change rather than an empty diff.

Alternatives: Accept the GKE defaults unwritten, or enable every control plane stream.

### Availability signal

Decision: Alert on a [Cloud Monitoring uptime check](https://cloud.google.com/monitoring/uptime-checks) against `/healthz` from three prober regions every 60 seconds, with a content matcher requiring `ok` and `validate_ssl` enabled.

Why: This platform has close to no organic traffic, so a condition on the load balancer's 5xx ratio evaluates an empty series at the moment an outage begins, and silence is indistinguishable from a quiet night. The check produces the traffic it alerts on, so it is both the load and the signal. Matching body content means a `200` from something that is not this workload still fails, and `validate_ssl` makes the same check an expiry alarm for a certificate that renews unattended.

Alternatives: Alert on load balancer response classes or backend health, which only fire when there is traffic to observe.

### Alert threshold

Decision: Open an incident only when more than one checker location is failing, and set `auto_close` to 30 minutes.

Why: One location failing is a network path somewhere on the internet, and paging on it is how an alert teaches its reader to dismiss it. Requiring two costs nothing in detection here: one zonal cluster behind one global load balancer has no partial-failure mode, so a real outage fails every location inside the same check period. The default `auto_close` of seven days would leave a self-recovered incident open when the next real one arrives.

Alternatives: Page on a single failing location, or on a proportion of locations.

## Load and scaling

### Workload autoscaling

Decision: A `HorizontalPodAutoscaler` on sky between two and eight replicas, scaling on CPU utilization at 70% of the request, with scale-up stabilization of 0s and scale-down stabilization of 300s written out. The replica count leaves the Deployment manifest.

Why: uvicorn serves each Pod from one process, so CPU tracks load closely and the metric is already collected. The minimum of two keeps the spread and the disruption budget intact at rest, and a floor of one would save nothing, because the node pool's floor of two is the cost. nginx serves a static page and is not the bottleneck. The stabilization windows are the defaults: react to load at once, and wait five minutes before removing a Pod.

Cost: Utilization is measured against the request, so a low request scales on almost no load, and `limits.cpu` in the quota caps the replica count before node capacity does. The pipeline applies the Deployment, so `replicas` has to leave both the manifest and its last-applied record, or a deploy resets the count. The pipeline Role cannot create the HPA, so an operator applies it.

Alternatives: Fixed replicas. Requests per second through a custom metrics adapter. The [Vertical Pod Autoscaler](https://cloud.google.com/kubernetes-engine/docs/concepts/verticalpodautoscaler), which resizes Pods rather than adding them and restarts them to do it.

### sky resource size

Decision: A CPU request of 350m and a limit of 1000m on sky, with the namespace quota at 5 CPU of requests, 13 CPU of limits and 16 Pods.

Why: At 100m and 500m, the HPA acted from 20 rps and the quota stopped it at five of eight replicas, and five Pods saturated at 60 rps with 31 to 48% of their CPU periods throttled while the busiest node used 61% of its CPU. The limit, not the node, was the ceiling. One uvicorn process cannot use more than one core, so a one-core limit leaves little to throttle. The request sets what the HPA's 70% means: at 350m the target is about 245m, around 12 rps a Pod. The quota covers the worst moment of a deploy at eight replicas: one surge Pod and two old Pods still in their `preStop` sleep, beside nginx's four and the smoke test Pod.

Cost: Five sky Pods request 1750m, and the two nodes have about 2000m free after system Pods, so a sixth Pod needs a third node. The quota no longer caps sky below its HPA maximum, so node capacity and the pool's maximum of three are what bound it.

Alternatives: No CPU limit, which removes throttling entirely but leaves `limits.cpu` in the quota unenforceable for sky. A higher request at the same limit, which delays scaling and keeps the throttling.

### Liveness probe under load

Decision: sky's liveness probe allows six failures at a 5s timeout, about a minute, before a restart. Readiness stays at three failures at 2s.

Why: Both probes asked the same question on the same schedule, so a Pod too busy to answer in 2s was restarted as well as taken out of rotation. A spike from 0 to 100 rps on two Pods restarted four Pods in five minutes, each restart refused connections while it came back, and the load balancer logged 270 `failed_to_connect_to_backend`. Readiness is the probe that should react to load: it removes a slow Pod from the load balancer and returns it when it recovers. Liveness is for a process that will not recover.

Cost: A Pod that has truly hung serves nothing for up to a minute before it restarts, though readiness has already removed it from the load balancer by then.

Alternatives: A separate liveness endpoint that answers without the application's own work, which the upstream application does not have. No liveness probe, which leaves a hung process running until someone notices.

### Scaling telemetry

Decision: Add the `CADVISOR`, `HPA`, `DEPLOYMENT` and `POD` packages to Managed Service for Prometheus.

Why: The failure modes this phase predicts are invisible in the existing metrics. A quota stall is desired replicas diverging from available ones, and a throttled Pod looks idle against its limit while it queues requests. Both become series on the dashboard rather than lines in a terminal.

Cost: The packages bill per sample ingested, so the weekly cost is measured again after they are enabled.

Alternatives: The `kubectl` recorder alone, which captures stalls and misses throttling.

### Load test tool

Decision: [k6](https://grafana.com/docs/k6/latest/), with arrival-rate executors and a threshold on each fixed-rate step.

Why: A closed-loop tool such as `hey`, `ab` or `wrk` waits for each response before sending the next request, so a slowing server receives less load and its latency is under-reported. An arrival-rate executor holds the rate regardless of response time. k6 evaluates a threshold over the whole run, so a single ramp trips long after the point of saturation; a threshold per step makes that point the last step that passes. The scripts live in the repository, so every run uses the same test.

Alternatives: vegeta or wrk2, which hold a rate and script poorly. Locust or JMeter, which model user journeys this platform does not have.

### Saturation criterion

Decision: A ramp step fails when p95 latency exceeds 500ms or errors exceed 1% among the requests sent after the step settles, and the run stops at the first failing step. A step settles 15s into a 60s step, or 90s into the 180s steps an autoscaling run uses.

Why: Stopping at the point of saturation measures capacity without holding the platform in overload while the uptime alert is armed. Judging a step from its first request let its opening seconds end a run: the keep-alive ramp stopped 3.4s into its 40 rps step, on 118 requests. An autoscaled workload is slow at the start of a step by design while the HPA adds Pods, so that part of the step says nothing about capacity.

Cost: A failing step runs for its settle time plus 10s before the run stops, so overload lasts longer. Runs judged with and without a settle window do not compare directly, which is why C0 reruns the baseline.

Alternatives: A fixed ramp to a fixed peak, which compares more simply and overloads the platform on every run. A longer `delayAbortEval` from the start of the run, which protects only the first step.

### Load source

Decision: Generate load from one `e2-standard-2` VM in `europe-west4`, on a throwaway VPC with SSH through IAP only, created and deleted with gcloud each session.

Why: A laptop on a home connection varies between runs and can saturate before the workload does. A nearby region keeps round-trip time small enough that latency changes belong to the platform, while traffic still arrives through the public load balancer. A separate VPC keeps the load source outside the platform network, and deleting it leaves `gke-vpc` as the only network.

Cost: The VM and its network are console state rather than configuration, so the runbook is what keeps each session's generator identical. The project holds a second network for the length of a session.

Alternatives: A laptop, which is free and unrepeatable. A Terraform-managed VM, which is reproducible and adds a module for a resource that lives for hours. A subnet on `gke-vpc`, which puts unmanaged resources in the Terraform-owned network.

### Alerting during load tests

Decision: Keep the uptime alert armed during every run.

Why: A page caused by load is evidence that the availability alert catches overload as well as an outage. Snoozing it tests a platform with its alerting removed.

Cost: A step pushed past saturation can open an incident. Stopping at the first failing step keeps that window short.

Alternatives: Snooze the alert for each run window.

### Graceful Pod exit

Decision: A `preStop` sleep of 35s on both workloads, using the kubelet's built-in [`sleep` action](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/#hook-handler-implementations), with `terminationGracePeriodSeconds` of 60.

Why: The NEG readiness gate holds an old Pod until its replacement is healthy in the load balancer, and nothing held it until its own endpoint had left. That took 12 to 13s, and a rollout at 20 rps failed 73 requests in the gap. A 20s sleep took sky to zero and left 4 failures on nginx: the detach completed 12s after the Pod stopped, and a few requests still reached it 28.6s after, while the change spread across the load balancer's proxies. 35s covers that tail. The built-in action needs no shell, so it works in both images and under the `restricted` standard.

Cost: Every replaced Pod stays `Terminating` 35s longer and holds its share of the namespace quota for that time. Two deploys 33s apart filled `limits.cpu` at 3000m of 3000m and both smoke tests were refused, so the two deploy workflows now share one concurrency group. The grace period includes the sleep, so raising the sleep without raising the grace period cuts the server's own shutdown short.

Alternatives: An `exec` hook running `sleep`, which depends on a shell neither image is required to carry. Connection draining on the backend service, which keeps connections that are already open and does nothing for a Pod that has stopped listening before its endpoint is removed.

### Backend keep-alive

Decision: Keep idle backend connections open for 620s on both workloads: `--timeout-keep-alive 620` on uvicorn and `keepalive_timeout 620s` on NGINX.

Why: The load balancer reuses a backend connection for up to 600s. A backend that closes it sooner can close it just as a request is sent on it, and the load balancer answers that request with a 503 `backend_connection_closed_before_data_sent_to_client`. uvicorn closed after 5s and NGINX after 65s. The baseline ramp saw 6 of these 503s, and the rollout runs saw 1, 3 and 8, including one on nginx and several outside any rollout.

Cost: Idle connections from the load balancer's proxies stay open for minutes rather than seconds, each holding a file descriptor and a little memory on the Pod.

Alternatives: Keep the defaults and retry on the client, which hides the error from one client and leaves it for every other.

## Project and process

### Project focus

Decision: Build a secure GCP hosted Kubernetes workload platform. Host an interesting custom workload on it.

Why: Keeps cloud and Kubernetes engineering as the primary work while providing a concrete workload to prove the platform.

Alternatives: Build an [application-first AI service](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/overview) or a dedicated self-hosted AI platform.

### First platform milestone

Decision: Extend the existing NGINX workload into one complete vertical slice before adding the AI workload or broader platform features.

Why: Reuses the deployed cluster, manifests, validation, and evidence while keeping the first milestone complete and testable.

Alternatives: Implement networking, policy, delivery, observability, and AI as separate horizontal workstreams.

### AI workload direction

Decision: Replace the planned deterministic manifest reviewer with agents that operate this platform: Security Command Center triage, an audited gateway for cluster reads, and a first responder scored against the Phase 10 drills.

Why: The reviewer would have been one more workload the platform hosts, and the platform already hosts two. Nothing in it needed this cluster to exist. The agents do. They read its findings, its events and its records, and the measurement worth having was already written down: [Phase 14](worklog/phase-14-close-the-baseline.md) named the overlap between Security Command Center and `.checkov.baseline` as the comparison worth making and left it open. Security Command Center has produced findings continuously since 2026-09-18 and nobody reads them.

Cost: Accepting submitted YAML from the internet was a bounded threat surface with a well understood shape. An agent holding cluster credentials is neither, and it is the harder boundary to defend. Milestone 4 keeps every agent read-only and Phase 16 carries the threat model pass, so the cost is paid deliberately rather than discovered later.

Alternatives: Keep the reviewer, which proves untrusted input handling that Cloud Armor and the rate limit already exercise. Or build a visitor-facing question surface over the project's own records, which stays available behind `/sky` because that workload already serves JavaScript, and is not ruled out by this.

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
- One namespace for every workload versus a namespace per workload, when a third workload or a second owner arrives

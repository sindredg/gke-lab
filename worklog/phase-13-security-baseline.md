# Worklog: Phase 13 Security Baseline

Date: 2026-09-17
Status: In progress.

## Goal

Measure the platform against its own [threat model](../reference/threat-model.md) rather than against a reading of it.

Phase 11 audited by inspection and found real things. Two findings since did not arrive that way. A public TLS scan graded the load balancer `B` on an SSL policy nobody had chosen, and modelling the trust boundaries showed that merge protection is not a control on the path to Google Cloud. Neither is visible in a manifest, which is the argument for this phase.

## Slice 1: The public surface

Status: Complete

`scripts/check-public-surface.sh` probes TLS versions, response headers, the HTTP redirect, and the DNS records that govern certificate issuance. It needs no credential and no cluster access.

```bash
./scripts/check-public-surface.sh
```

```text
Checking the public surface of sindrg.com

known     tls10-refused    server accepted tls1
known     tls11-refused    server accepted tls1_1
ok        tls12-accepted   server accepted tls1_2
ok        tls13-accepted   server accepted tls1_3
ok        http-redirect    plain HTTP redirects to HTTPS
known     hsts             strict-transport-security missing on / /sky/
known     csp              content-security-policy missing on / /sky/
known     nosniff          x-content-type-options missing on / /sky/
known     referrer-policy  referrer-policy missing on / /sky/
known     frame-ancestors  content-security-policy missing on / /sky/
known     caa              no CAA record
known     dnssec           no DS record

3 ok, 9 known open, 0 regressed, 0 resolved, 0 inconclusive
```

Every finding the threat model predicted for this boundary is open, and nothing it did not predict turned up. Three properties hold: TLS 1.2 and 1.3 both negotiate, and plain HTTP redirects to HTTPS before any Pod sees it.

### What the run settles

Two findings were written into the threat model as unverified, because no file in this repository describes DNS state. Both could have turned out closed. Neither did.

**No CAA record.** Certificate issuance for this domain is proved by a DNS record, and no CA is excluded from honouring that proof. Anyone who can edit the Cloudflare zone can obtain a valid certificate for `sindrg.com` from any CA that will issue one. Private nodes, Workload Identity Federation, Pod Security and the network policies are all irrelevant on this path, because it never touches the cluster.

**No DS record.** The zone is unsigned, so the DNS answers carrying that proof are not authenticated either.

The two compound rather than add. The certificate depends on a DNS answer, the DNS answer is unauthenticated, and no CAA record constrains who will accept it. That is the threat model's second highest ranked path, and it is now measured rather than suspected.

**TLS 1.0 and 1.1 accepted**, confirming the public scan independently. Google's default SSL policy permits them and no policy is attached to the Gateway.

**Five response headers missing on both paths.** HSTS, CSP, `X-Content-Type-Options`, `Referrer-Policy` and a `frame-ancestors` directive are absent from the nginx root and from `/sky/` alike.

A first draft of this worklog said the fix was to set them once at the Gateway. That is not possible. Gateway API puts filters on an HTTPRoute rule, and a Gateway-wide response header filter exists only as an implementation-specific extension that this controller does not provide. The header set is therefore declared on every rule serving the host, which is three rules across two files, and keeping them identical is a review problem rather than a configuration one.

### What the script refuses to do

Three times while writing it, a check reported a result it had not established.

The first was the important one. OpenSSL 3 refuses TLS 1.0 client-side at its default security level, and the resulting error is nearly indistinguishable from a healthy server refusing the same connection. Read naively, a server that happily speaks TLS 1.0 reports as a pass. Legacy probes now set `SECLEVEL=0` so the offer is actually made, and a client-side refusal is reported as inconclusive rather than as success.

The second and third were the same mistake in other clothes: a request that never arrived read as a missing header, and an error status from an intermediary read as a missing redirect. Neither is evidence about the origin.

So the script has three outcomes rather than two, and the third never counts as a pass. A control whose verification silently fails open is worse than one known to be absent, because it appears in a worklog as evidence.

The run above is the first with nothing inconclusive: every probe reached the origin and every check returned a verdict.

### How it stays true

Findings the threat model records are listed in the script, so it gates against regression rather than against work Phase 14 has not done. A listed check that starts passing also fails, and names the line to delete. The list cannot quietly outlive the findings it describes.

Evidence: run recorded above. Scheduled daily by `.github/workflows/security-scan.yml`.

## Slice 2: Static analysis of the Terraform and the manifests

Status: Complete

checkov 3.3.19 over both trees, wired into `ci.yml` so it runs on every pull request.

| Tree | Passed | Failed |
| --- | --- | --- |
| `kubernetes/` | 194 | 1 |
| `terraform/` | 30 | 9 |

### Two checks verified wrong here

Skipped in `.checkov.yml` with their reason, because a false positive silently carried in a baseline becomes indistinguishable from an accepted risk.

`CKV_GCP_12` wants NetworkPolicy enabled and reads the legacy `network_policy` block. This cluster sets `datapath_provider = "ADVANCED_DATAPATH"`, and Dataplane V2 enforces NetworkPolicy without that block. Phase 4 recorded an unlabelled client denied by both name and address.

`CKV_GCP_69` wants the GKE metadata server enabled and reads the cluster resource. `workload_metadata_config` is set to `GKE_METADATA` on the node pool resource, with legacy endpoints disabled.

The second was worth confirming rather than assuming. Had it been real, a compromised Pod could have reached the node's service account through the metadata endpoint, and the threat model's claim that boundary 3 leaves a Pod close to inert would have been wrong.

### Two findings the model had already reached

`CKV_GCP_125` flags the GitHub Actions OIDC trust policy and `CKV_GCP_66` flags the absence of Binary Authorization. These are threat model findings 2 and 10, arrived at independently by a tool that never read the model.

### The rest

Recorded in `.checkov.baseline` rather than skipped, because each is a decision to make rather than a default to bury: VPC flow logs against the cost posture, master authorized networks against a control plane that has no IP endpoint, Google Groups for RBAC against a single operator, CSEK against a platform with nothing confidential at rest, and client certificate authentication which GKE disables by default but does not state explicitly.

One new finding, low severity and genuine: nginx runs as uid 101 where `CKV_K8S_40` wants a uid above 10000, to avoid collision with a host user. `sky` already runs as 10001.

## Slice 3: Cluster assessment

Status: Not started

Kubescape against the MITRE ATT&CK and NSA frameworks, one-shot from an operator context rather than as an in-cluster agent, and whatever Security Command Center already reports.

## Slice 4: Account controls

Status: Not started

Threat model finding 8. Multi-factor authentication, who holds write access, and whether `main` requires status checks and an up-to-date branch. The model assumes all three and no scan reaches any of them.

## Open question raised during the phase

CI did not run on two consecutive pushes to the pull request carrying this work. The branch advanced twice, confirmed against the remote, and the only workflow run on the branch remained the one from the first commit. The pull request displayed three passing checks throughout, all of them validating a commit two behind the branch head.

Nothing merged, and the cause was not established. It is recorded because the shape is the same one this phase exists to find: a control reporting success for work it did not examine. Whether `main` requires a branch to be up to date before merging decides whether that shape can reach production, and that is Slice 4's question.

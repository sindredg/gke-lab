# Threat Model

Date: 2026-09-17
Scope: the GKE platform, the two workloads it serves, the delivery pipeline, and the DNS and certificate path that publishes them.
Revisit when: Phase 15 begins. Accepting submitted manifests from the internet changes this model substantially, and the baseline is easier to establish on the system as it stands today.

## Method

Four questions, in order: what are we working on, what can go wrong, what are we going to do about it, and did we do a good job. This document answers the first two and proposes responses for the third. The fourth is Phase 13's continuous verification, because a control's state on the day it was reviewed is not evidence that it holds now.

Threats are enumerated with STRIDE against each trust boundary rather than against each component. A boundary is where authority changes hands, which is where the interesting failures are. Dismissals are recorded alongside findings; a threat model that lists only what went wrong cannot be checked for coverage.

LINDDUN was considered and not used. It models privacy harms against personal data, and this platform processes none.

Every threat ends in one of four responses: eliminate, mitigate, transfer, or accept. An accepted risk is recorded here with its reason. A mitigated one becomes an entry in [decisions.md](../decisions.md) once the mitigation is chosen, because that file holds what was decided and this one holds what it was decided against.

## What is at stake

The application has no database, no authentication, no API key, and no personal data. The same question returns the same answer. That removes confidentiality of user data from this model entirely, and with it most of what a threat model normally spends its length on.

What remains:

| Asset | Why it matters | Worst realistic outcome |
| --- | --- | --- |
| Integrity of what `sindrg.com` serves | The domain is a public portfolio under the author's name | Defaced or malicious content served from a trusted domain |
| The Google Cloud project | Compute that can be spent by someone else | Resource abuse against the credit balance |
| Availability of the public demo | People are pointed at it deliberately | The demo is down when it is being looked at |
| The platform's own evidence | The worklogs are the deliverable | A claim in this repository turns out not to hold |

The first row is the crown jewel, and it is worth stating plainly because the controls are not currently built for it. Almost every control on this platform defends confidentiality and containment. The asset is integrity of a public identity.

## Trust boundaries

| # | Boundary | Guarded by |
| --- | --- | --- |
| 1 | Internet to Gateway | TLS, nothing else |
| 2 | Gateway to Pod | NetworkPolicy on Google's load balancer ranges |
| 3 | Pod to cluster | PSA `restricted`, no token mounted, default-deny both directions |
| 4 | GitHub Actions to Google Cloud | Workload Identity Federation, namespaced RBAC |
| 5 | `sky` repository to the pipeline | The pinned commit in `.github/sky-upstream.ref` |
| 6 | DNS and certificate issuance | Domain control proved by DNS record |
| 7 | The GitHub account to everything | Outside both repositories |
| 8 | Public registries to the running image | Digest and version pinning, Dependabot |

## Adversaries

| Adversary | Capability | Interest | Likelihood |
| --- | --- | --- | --- |
| Opportunistic scanner | Automated, untargeted, high volume | Any reachable compute | Continuous, happening now |
| Curious reader | Manual probing of a published portfolio | Finding the gap between claim and reality | Likely, by design |
| Account compromise | Everything the account holds | Whatever the account reaches | Low probability, highest impact |
| Supply chain actor | A malicious commit or package upstream | Broad, untargeted | Low, and rising |

There is no targeted adversary in this model. Nothing here is worth a dedicated effort, and assuming one would distort every priority below.

## Boundary 1: Internet to Gateway

Public, unauthenticated, and unrated. The only boundary an opportunistic adversary reaches without help.

| | Threat | State |
| --- | --- | --- |
| S | No client identity exists to spoof | Not applicable by design |
| T | Downgrade or interception in transit | **Closed, measured.** `k8-lab-gateway-ssl-policy` sets a TLS 1.2 floor on the `MODERN` profile, attached by `GCPGatewayPolicy`. The script reports TLS 1.0 and 1.1 refused, 1.2 and 1.3 accepted, and HSTS present on both paths at `max-age=86400`. SSL Labs grades `A`. The short `max-age` is deliberate, so it is `A` rather than `A+` |
| R | Request attribution | Accepted. `sky` runs with `--no-access-log`, so request-level records come from the load balancer alone. Nothing here is transacted, so there is nothing to repudiate |
| I | Disclosure of served content | Not applicable. Nothing served is confidential. `/version` reveals the exact upstream commit, which is public already |
| D | Exhaustion from a single client | **Mitigated, unproven under load.** `k8-lab-gateway-rate-limit` throttles one address to 300 requests a minute, attached to each backend by `GCPBackendPolicy`. Phase 12 measured that one client can otherwise drive the namespace to its quota. `ResourceQuota` still bounds the blast radius at eight Pods. The flood test that would prove it is Phase 14's exit criterion |
| E | No authorization exists at this boundary | Not applicable |

Response headers other than HSTS sit on this boundary too, and finding 6 is only partly closed. `X-Content-Type-Options` and `Referrer-Policy` are present on both paths; CSP and `frame-ancestors` are absent from the nginx root and from `/sky/`, pending [sky#59](https://github.com/sindredg/sky/pull/59).

## Boundary 2: Gateway to Pod

| | Threat | State |
| --- | --- | --- |
| S | Traffic impersonating the load balancer | Residual, low. The NetworkPolicy admits `130.211.0.0/22` and `35.191.0.0/16`, which are shared Google ranges rather than this load balancer. Pods hold private addresses in a VPC those ranges cannot route to arbitrarily, so this is defence in depth rather than an exposure |
| T | Modification between load balancer and Pod | Accepted. The hop is plaintext HTTP to port 8080 inside Google's network. Terminating TLS a second time at the Pod is disproportionate here |
| I | Disclosure on that hop | Accepted, same reason |
| D | Covered at boundary 1 | |
| E | Not applicable | |

## Boundary 3: Pod to cluster

The most heavily defended boundary in the system, and the one an adversary gains least from crossing.

A remote code execution in `sky` — the realistic route being a dependency vulnerability in FastAPI, Starlette or uvicorn — lands in a container with no service account token mounted, a read-only root filesystem, every capability dropped, `runAsNonRoot` at uid 10001, `seccompProfile: RuntimeDefault`, PSA `restricted` enforced at admission, and **egress denied by default with only kube-dns permitted**.

| | Threat | State |
| --- | --- | --- |
| S | Impersonating another workload | Mitigated. No token to present |
| T | Persistence on the filesystem | Mitigated. Read-only root; `/tmp` is an `emptyDir` that does not survive the Pod |
| R | Action attribution inside the cluster | Accepted. Audit logging is on; nothing in the Pod acts on the API |
| I | Exfiltration | Mitigated, with one residual. There is no egress path out of the namespace except DNS, so no callback, no upload, and no mining pool. **DNS remains a low-bandwidth channel out**, and closing it is not possible without breaking name resolution |
| D | Consuming the namespace | Mitigated. Requests, limits, `LimitRange` and `ResourceQuota` |
| E | Privilege escalation to the node | Mitigated. `allowPrivilegeEscalation: false`, capabilities dropped, PSA `restricted`, Shielded nodes with Secure Boot |

DNS tunnelling is the honest residual here and is accepted. It is slow, noisy in logs that are already queryable after Phase 11, and there is nothing in the Pod worth the bandwidth.

## Boundary 4: GitHub Actions to Google Cloud

No key exists to steal, which is the point of federation. The consequence is that the **account is the key**.

| | Threat | State |
| --- | --- | --- |
| S | A token from another repository | Mitigated. `attribute_condition` on `assertion.repository`, documented in [the federation reference](iam-and-federation.md#attribute-condition) |
| T | What a compromised pipeline can change | Bounded. `artifactregistry.writer` on one repository, `container.clusterViewer` for reach only, and a namespaced Role holding `patch` on Deployments with no `create` or `delete`, no Secrets access, and no reach outside `demo` |
| R | Attribution of a deployment | Mitigated. Cloud Audit Logs record the federated principal |
| I | Reading project state | Bounded by the same grants |
| D | Filling the namespace quota | Observed already: Phase 12 recorded two concurrent rollouts exhausting `limits.cpu`, which is why both delivery workflows share a concurrency group |
| E | **Branch push to Google Cloud credentials** | **Open as a residual, not as a defect.** The condition and the `principalSet` both bind on `attribute.repository`. `attribute.ref` is mapped but not conditioned. Any workflow on any branch of this repository can therefore mint pipeline credentials |

The last row needs care, because the choice was made deliberately and is recorded in [decisions.md](../decisions.md#federation-trust-boundary): binding to the repository is stable where a branch is not, and the alternative breaks on every branch rename. That reasoning stands.

What the decision does not state is the consequence: **merge protection is not a control on the path to Google Cloud.** Required checks and pull request review govern what reaches `main`. They do not govern what a branch push can do, and a branch carrying a workflow that calls `google-github-actions/auth` receives the pipeline identity without ever being reviewed. The path is only open to an actor who already holds write access, which makes this a question of how much the account compromise in the adversary table is worth, not a question of whether an outsider can walk in.

The trade-off should be re-decided with that consequence written down. Scoping the condition to `refs/heads/main` would close it at the cost of the `workflow_dispatch` bootstrap path, which currently exists to publish an image before the Deployment exists.

Blast radius if this boundary falls, stated plainly: push an image, and patch the Deployment to run it. That is arbitrary content served at `sindrg.com/sky` — the crown jewel, reached without touching any of boundary 3's defences. PSA still blocks a privileged Pod, the quota still bounds the compute, and egress is still denied, so the project is not a mining platform. The integrity of the domain is what is lost.

## Boundary 5: The sky repository to the pipeline

| | Threat | State |
| --- | --- | --- |
| T | An unreviewed upstream commit reaching production | **Mitigated, with a residual.** `watch-sky.yml` now queries the upstream SHA's check runs and refuses to propose a pin whose CI is not green, counting anything unfinished as unknown rather than as a pass. The residual stands: no workflow event fires from a workflow token, so this repository's own CI still does not run on the pin bump. The upstream commit is validated; the bump itself is reviewed by a human reading a diff |
| S | A commit from an unexpected author | Accepted for now. The workflow fetches by SHA and verifies it resolves, but checks neither signature nor authorship |
| R | What was deployed and when | Mitigated. The pin is a file with history, and the image tag carries the upstream SHA |

The pin itself is a strong control and is worth keeping in view: production does not follow upstream's `main`, it follows a commit a human merged. The weakness was what informed that human, and querying `sky`'s check runs for the SHA turned out to be a small change to an existing workflow. It has shipped.

## Boundary 6: DNS and certificate issuance

The boundary nothing in either repository currently touches.

| | Threat | State |
| --- | --- | --- |
| S | A certificate issued for this domain by another CA | **Open, measured.** Certificate issuance is proved by a DNS record. Anyone with access to the Cloudflare zone can prove control to any CA and obtain a valid certificate for `sindrg.com`. None of the cluster's hardening is on this path. `scripts/check-public-surface.sh` reports no CAA record, so no CA is excluded |
| T | Redirecting the domain | **Open, measured.** A zone edit points the name anywhere, and the same run reports no DS record, so the zone is unsigned and its answers are not authenticated |
| D | Silent renewal failure | **Open.** Google renews automatically, so a broken authorization surfaces only when the certificate expires. This has precedent here: `PER_PROJECT_RECORD` is in the Terraform specifically because `FIXED_RECORD` collided with Cloudflare's own TXT record at `_acme-challenge` |

## Boundary 7: The GitHub account

Outside both repositories, and the highest-impact path in the model. Write access to `k8-lab` leads to Google Cloud by boundary 4; write access to `sky` leads to the same place more slowly by boundary 5.

This model originally **assumed** multi-factor authentication on the account, that write access is held only by its owner, and that `main` is protected with required checks. All three are load-bearing, none were verified by anything in this repository, and Phase 13 measured them. One assumption was wrong.

| Control | Measured state |
| --- | --- |
| Multi-factor authentication | Enabled. Not obtainable from the API for a personal account, confirmed by the owner at `github.com/settings/security` |
| Write access | `sindredg` is the sole collaborator on both repositories, admin on each. No other user or team |
| `main` on `k8-lab` | Protected by the `Protect main` ruleset, active. It existed from 2026-08-28 with `conditions.ref_name.include` empty, so it matched no branch and enforced nothing for three weeks. Retargeted to `~DEFAULT_BRANCH` with `strict_required_status_checks_policy` on |
| `main` on `sky` | **Open.** Neither a ruleset nor classic protection. Unaddressed, carried to Phase 14 |

One residual on `k8-lab`: the ruleset requires `Terraform`, `Kubernetes` and `Docs and scripts`, three of the five checks that run. `Static analysis` (checkov) and `Public surface` report but do not gate, so a pull request merges with either of them red.

Evidence: [Phase 13 worklog](../worklog/phase-13-security-baseline.md#slice-4-account-controls).

## Boundary 8: Public registries to the running image

| | Threat | State |
| --- | --- | --- |
| T | A malicious dependency or base image | Mitigated. Base image by digest, Python dependencies pinned, actions pinned by SHA, Dependabot proposing bumps on all three |
| T | A malicious bump merged unreviewed | Residual. A Dependabot pull request is still a pull request, and the review is a human reading a diff |
| S | An image that did not come from this pipeline | **Open.** `provenance: false` is set in the build, no SBOM is produced, nothing is signed, and Binary Authorization is not enforced. The only control is that the pipeline identity is the sole writer to the repository, which is an authorization control rather than an attestation |

The last row matters less than it first appears, and the ordering below reflects that. Attestation proves *this pipeline built it*. It says nothing about whether the commit should have been built, which is boundary 5's question and the cheaper one to answer first.

## Attack paths, ranked

Ranked by likelihood multiplied by impact against the assets above, not by how interesting they are. The ranking is as modelled, before Phase 13; the last column records what has since been put on each path.

| Path | Likelihood | Impact | Net | Control now |
| --- | --- | --- | --- | --- |
| Exhaustion from an unrated public endpoint | Happening continuously | Cost and availability | **Highest** | Rate limiting, 300 a minute per address |
| Account compromise to arbitrary content on the domain | Low | Crown jewel | **High** | MFA and a ruleset that now matches `main`. `sky` still open |
| Certificate issued through the DNS zone | Low | Crown jewel, and invisible from inside the platform | **High** | None. Findings 3 and 9 both open |
| Downgrade against TLS 1.0 or 1.1 | Low | Low; nothing confidential in transit | Medium, and visibly wrong | TLS 1.2 floor. Closed |
| An upstream commit reaching production unvalidated | Moderate | Depends entirely on the commit | Medium | Upstream CI queried before the pin is proposed |
| RCE in the application | Low | Very low; the Pod is close to inert | **Lowest** | Six overlapping, unchanged |

The shape of that table was the finding. Six overlapping controls sat on the bottom row, and the top three had one, none, and none. Phase 13 put a control on four of the six rows, including the highest ranked. The third row is the one left untouched, and it is the one nothing in this repository can see.

That is not a criticism of the work. Containment that good is unusual, and it is why the bottom row ranks last. It is what happens when a platform is hardened by category — Pod security, network policy, image provenance — rather than by adversary. Categories are how the guides are organised, so this is the normal outcome of following them well.

## What this platform does not defend

Recorded so that the absence is a decision rather than an oversight.

- **Volumetric denial of service.** Quota bounds the blast radius. Nothing absorbs a real flood, and nothing needs to.
- **Insider threat.** One operator. Separation of duties is not meaningful at this size.
- **Confidentiality of served content.** All of it is public, deliberately.
- **Data at rest.** There is none.
- **Availability during a zonal outage.** A zonal cluster is a recorded cost decision, and the regional comparison is a later gate.
- **A targeted, funded adversary.** Out of scope, per the adversary table.

## Findings

Carried into Phase 13 for verification and Phase 14 for the work. Ranked as above, not by boundary. Status is as Phase 13 measured it.

| # | Boundary | Finding | Proposed response | Status after Phase 13 |
| --- | --- | --- | --- | --- |
| 1 | 1 | No rate limiting on the public endpoint | Mitigate | Closed. 300 requests a minute per address, live. Not yet proven under a flood |
| 2 | 4 | Merge review is not a control on the path to Google Cloud | Re-decide with the consequence recorded | Open. Carried to Phase 14 |
| 3 | 6 | No CAA record, so no CA is excluded from issuing for this domain | Mitigate | Open, measured. Carried to Phase 14 |
| 4 | 6 | Renewal failure is silent | Mitigate | Open. Carried to Phase 14 |
| 5 | 1 | TLS 1.0 and 1.1 accepted; no SSL policy defined | Mitigate | Closed, measured. TLS 1.2 floor, both refused |
| 6 | 1 | No HSTS, and no other response security headers | Mitigate | Partly closed. HSTS, `nosniff` and `Referrer-Policy` live; CSP and `frame-ancestors` open, carried to Phase 14 |
| 7 | 5 | The pin bump is the one pull request CI does not validate | Mitigate | Closed. Upstream CI is queried before the pin is proposed |
| 8 | 7 | Account controls are assumed, not verified | Verify | Closed for `k8-lab`, and one assumption was wrong. `sky`'s `main` is unprotected, carried to Phase 14 |
| 9 | 6 | No DS record, so the zone is unsigned | Decide | Open, measured. Carried to Phase 14 |
| 10 | 8 | No provenance, SBOM, signature, or admission policy | Mitigate, after 7 | Open. Carried to Phase 14 |
| 11 | 3 | DNS is the one egress channel out of the namespace | Accept | Accepted |
| 12 | 2 | Shared Google ranges admitted by NetworkPolicy | Accept | Accepted |

Findings 1, 3, 5, 6 and 9 are measured rather than reasoned: [the Phase 13 worklog](../worklog/phase-13-security-baseline.md) records every run. Findings 3 and 9 were written here as unverified and might have turned out closed; both are open.

Finding 8 was the one the highest ranked path rests on, and verifying it found the assumption false. `k8-lab`'s ruleset had been active for three weeks while matching no branch. Nothing in this repository would have shown that, which is the argument for the phase.

Phase 13 closed no finding by writing about it. Each closure above has a command and its output in the worklog.

## References

- [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/)
- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [MITRE ATT&CK for Containers](https://attack.mitre.org/matrices/enterprise/containers/)
- [Hardening your GKE cluster](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster)
- [SLSA](https://slsa.dev/)
- [decisions.md](../decisions.md), for what was decided and why
- [IAM and Workload Identity Federation reference](iam-and-federation.md), for the federation mechanics
- [Networking reference](networking.md), for the ingress and egress paths

# Threat Model

Date: 2026-09-17
Scope: the GKE platform, the two workloads it serves, the delivery pipeline, and the DNS and certificate path that publishes them.
Revisit when: Phase 16 begins. Giving an agent cluster credentials and an audited path to use them adds a trust boundary this model does not have, and the baseline is easier to establish on the system as it stands today.

Phase 15 arrives before that revision and changes two boundaries without closing anything. Those changes are recorded where they land, on [boundary 3](#boundary-3-pod-to-cluster) and [boundary 5](#boundary-5-upstream-repositories-to-the-pipeline), and are rated at the Phase 16 pass rather than here. The findings table below is still as Phase 13 measured it and is not restated for them.

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
| 5 | Upstream repositories to the pipeline | The pinned commit in `.github/sky-upstream.ref`, and in `.github/ai-k8s.ref` from Phase 15 |
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
| D | Exhaustion from a single client | **Mitigated, measured under load.** `k8-lab-gateway-rate-limit` throttles one address to 300 requests a minute, attached to each backend by `GCPBackendPolicy`. Phase 14 flooded it from one address at 15 rps: 593 of 1200 requests refused with `429`, the first at t+18.0s after 292 consecutive `200`s, and `demo-budget` flat at `pods: 4/16` throughout. A second run at 125 rps isolates the throttle against Phase 12d, which drove that rate unthrottled: sky reached 3 of 8 replicas where Phase 12d reached 8 of 8, so the throttle caps scale-out rather than preventing it. `ResourceQuota` still bounds the blast radius at eight Pods |
| E | No authorization exists at this boundary | Not applicable |

Response headers other than HSTS sit on this boundary too, and finding 6 is closed. `X-Content-Type-Options` and `Referrer-Policy` are present on both paths, and so is a Content Security Policy: `default-src 'none'` on the nginx root from [#100](https://github.com/sindredg/k8-lab/pull/100), and the application's own `default-src 'self'` on `/sky/` once [#106](https://github.com/sindredg/k8-lab/pull/106) moved the pin to [sky#59](https://github.com/sindredg/sky/pull/59).

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

The table above describes `demo`, and stays true of `demo`. Phase 15 adds a second namespace, `agents`, where two of these rows read differently. The triage worker reaches Pub/Sub, Vertex AI, Cloud Storage and Cloud Logging, so egress is a real channel there rather than DNS alone, and it holds a Google Cloud identity through Workload Identity rather than no token at all. Both are why it is a separate namespace instead of a third Deployment in `demo`, recorded in [decisions.md](../decisions.md#agent-namespace): the alternative was widening egress for the two workloads that serve the public site.

Neither is assessed here, and they no longer stand at the same state. The service account scoped to four roles was built. The egress policy naming only the Google APIs the worker calls was not: NetworkPolicy cannot match hostnames, so the rule admitting them is everything outside the cluster's own address space on TCP 443, not named ranges, and the `agents` namespace currently admits all non-private destinations on that port. The VPC has Cloud NAT, so this is a working route to the internet rather than a theoretical one, and boundary 3's "no callback, no upload, and no mining pool" no longer holds for this namespace.

The narrow option needs a Private Google Access DNS zone plus the `199.36.153.4/30` `restricted.googleapis.com` range. The subnet is already half-configured for it, since `private_ip_google_access = true`. Accepted for now and rated at the Phase 16 pass. Recorded now so the gap is visible while it is open, and because finding 11 otherwise reads as covering a cluster it no longer describes.

## Boundary 4: GitHub Actions to Google Cloud

No key exists to steal, which is the point of federation. The consequence is that the **account is the key**.

| | Threat | State |
| --- | --- | --- |
| S | A token from another repository | Mitigated. `attribute_condition` on `assertion.repository`, documented in [the federation reference](iam-and-federation.md#attribute-condition) |
| T | What a compromised pipeline can change | Bounded. `artifactregistry.writer` on one repository, `container.clusterViewer` for reach only, and a namespaced Role holding `patch` on Deployments with no `create` or `delete`, no Secrets access, and no reach outside `demo` |
| R | Attribution of a deployment | Mitigated. Cloud Audit Logs record the federated principal |
| I | Reading project state | Bounded by the same grants |
| D | Filling the namespace quota | Observed already: Phase 12 recorded two concurrent rollouts exhausting `limits.cpu`, which is why both delivery workflows share a concurrency group |
| E | Branch push to Google Cloud credentials | Mitigated in Phase 14. The condition binds `assertion.repository` and `assertion.ref`, so only `refs/heads/main` reaches the pool. The `principalSet` still binds the repository, so the provider is the single place the ref is enforced |

This was open when the model was written, and open deliberately: [decisions.md](../decisions.md#federation-trust-boundary) had chosen the repository alone because a branch changes over a project's life and a repository does not. That reasoning was sound and left a consequence unstated.

The consequence is that **merge protection was not a control on the path to Google Cloud.** Required checks and pull request review govern what reaches `main`; they do not govern what a branch push can do, and a branch carrying a workflow that calls `google-github-actions/auth` received the pipeline identity without ever being reviewed. The path was only open to an actor who already held write access, which made it a question of what the account compromise in the adversary table is worth rather than whether an outsider could walk in.

Written down that way, the trade-off reversed. The cost is smaller than it first looked: `workflow_dispatch` still works from `main`, so the bootstrap path survives, and what is actually lost is exercising delivery from a branch, plus a branch rename breaking it until the condition follows.

Blast radius if this boundary falls, stated plainly: push an image, and patch the Deployment to run it. That is arbitrary content served at `sindrg.com/sky` — the crown jewel, reached without touching any of boundary 3's defences. PSA still blocks a privileged Pod, the quota still bounds the compute, and egress is still denied, so the project is not a mining platform. The integrity of the domain is what is lost.

## Boundary 5: Upstream repositories to the pipeline

Two repositories cross this boundary by the same mechanism. `sky` has since 2026-09. `ai-k8s` joins it in Phase 15, and carries more.

| | Threat | State |
| --- | --- | --- |
| T | An unreviewed upstream commit reaching production | **Mitigated, with a residual.** `watch-sky.yml` now queries the upstream SHA's check runs and refuses to propose a pin whose CI is not green, counting anything unfinished as unknown rather than as a pass. The residual stands: no workflow event fires from a workflow token, so this repository's own CI still does not run on the pin bump. The upstream commit is validated; the bump itself is reviewed by a human reading a diff |
| S | A commit from an unexpected author | Accepted for now. The workflow fetches by SHA and verifies it resolves, but checks neither signature nor authorship |
| R | What was deployed and when | Mitigated. The pin is a file with history, and the image tag carries the upstream SHA |

The pin itself is a strong control and is worth keeping in view: production does not follow upstream's `main`, it follows a commit a human merged. The weakness was what informed that human, and querying `sky`'s check runs for the SHA turned out to be a small change to an existing workflow. It has shipped.

### The agent edge carries more than the sky edge

The mechanism is identical and the stakes are not. A malicious commit to `sky` changes what a webpage renders, which the integrity asset already ranks first and the pin already governs. A malicious commit to `ai-k8s` changes prompt templates and the deterministic matcher, which together decide whether a security finding is reported as accepted, as contradicting a recorded decision, or not reported at all. That is a control over what the platform's owner gets told about the platform.

Three things narrow it, and none of them is new machinery. The corpus the agent cites stays in this repository, so a commit to `ai-k8s` cannot add the `.checkov.baseline` entry a forged acceptance would have to resolve against. The pin is reviewed here by the same human reading the same kind of diff. And the same check-run query that guards the `sky` pin guards this one from the first bump rather than as a follow-up, because finding 7 already established that a pin proposed without reading upstream CI is the weak step.

The residual is the same one: this repository's CI does not run on a pin bump, so the human reading the diff is the control. Carried forward to the Phase 16 revision rather than closed here.

Re-ranked on 2026-09-20, against this second edge and against Phase 19's ability to open a pull request in `k8-lab`. The deferred acceptance on [boundary 8](#boundary-8-public-registries-to-the-running-image) holds. Signing proves which pipeline built an image, and neither new edge produces an image from a different pipeline: both produce a commit this pipeline would build and sign correctly.

Phase 19 does not widen this edge either. Its scope check rejects any proposal touching the evidence corpus, so the narrowing above, that nothing the agent commits can add the `.checkov.baseline` entry a forged acceptance would have to resolve against, still holds once the agent can open pull requests here.

One control on this boundary moves earlier instead. Threat S above, a commit from an unexpected author, was accepted because `sky`'s commits are all the owner's. `ai-k8s` holds the logic that decides what the owner is told about the platform's security, and has one author from its first commit, so its pinned commit is checked for signature and authorship before it is built. Recorded in [decisions.md](../decisions.md#supply-chain-control-timing) and carried as a Phase 15 item rather than waiting for the Phase 16 pass.

## Boundary 6: DNS and certificate issuance

The boundary nothing in either repository currently touches.

| | Threat | State |
| --- | --- | --- |
| S | A certificate issued for this domain by another CA | **Mitigated 2026-09-18, measured.** `sindrg.com` now publishes `0 issue "pki.goog"` and `0 issuewild ";"`, verified on two public resolvers, so Google Trust Services is the only authorised CA and no CA may issue a wildcard. The residual is unchanged in kind: CAA binds a compliant CA at issuance, and anyone with access to the Cloudflare zone can still edit the record before proving control. None of the cluster's hardening is on this path |
| T | Redirecting the domain | **Mitigated 2026-09-18, measured.** The zone is signed: the DS is published in `.com`, two public resolvers return it, and `dig +dnssec` sets `ad`, so the answers are authenticated. The residual is a zone edit, which signing does not address. Anyone holding the Cloudflare account can still point the name anywhere, and sign it |
| D | Silent renewal failure | **Mitigated.** Google renews automatically, so a broken authorization would otherwise surface only at expiry, and there is precedent: `PER_PROJECT_RECORD` is in the Terraform because `FIXED_RECORD` collided with Cloudflare's own TXT at `_acme-challenge`. `cert-expiry` now reads the served certificate daily and fails below 21 days, which is a stalled renewal rather than a healthy one |

The record only means what it says while Cloudflare's Universal SSL is off. With it on, Cloudflare adds CAA records for its own partner CAs to any zone that has one, does not show them in its dashboard, and documents the list as not exhaustive. Phase 14 measured eleven records where the zone held two, and RFC 8659 takes the union at a name, so the injected `issuewild` entries re-authorised the issuance `issuewild ";"` exists to forbid. Turning Universal SSL back on silently reverses this row. Evidence: [Phase 14](../worklog/phase-14-close-the-baseline.md#finding-universal-ssl-makes-the-authorised-issuer-set-cloudflares-to-change).

## Boundary 7: The GitHub account

Outside both repositories, and the highest-impact path in the model. Write access to `k8-lab` leads to Google Cloud by boundary 4; write access to `sky` leads to the same place more slowly by boundary 5.

This model originally **assumed** multi-factor authentication on the account, that write access is held only by its owner, and that `main` is protected with required checks. All three are load-bearing, none were verified by anything in this repository, and Phase 13 measured them. One assumption was wrong.

| Control | Measured state |
| --- | --- |
| Multi-factor authentication | Enabled. Not obtainable from the API for a personal account, confirmed by the owner at `github.com/settings/security` |
| Write access | `sindredg` is the sole collaborator on both repositories, admin on each. No other user or team |
| `main` on `k8-lab` | Protected by the `Protect main` ruleset, active. It existed from 2026-08-28 with `conditions.ref_name.include` empty, so it matched no branch and enforced nothing for three weeks. Retargeted to `~DEFAULT_BRANCH` with `strict_required_status_checks_policy` on |
| `main` on `sky` | Protected in Phase 14. Classic protection requiring `Lint and test` and `Frontend tests`, both of which run on every pull request |

One residual on `k8-lab`, narrowed rather than closed. The ruleset requires `Terraform`, `Kubernetes` and `Docs and scripts`; Phase 14 added a classic rule requiring `Static analysis`. Two mechanisms now govern one branch with disjoint check lists, which is not weaker than one but is harder to read than it should be. `Public surface` gates nothing by design: it runs on two paths only, so requiring it would leave every other pull request pending.

Evidence: [Phase 13 worklog](../worklog/phase-13-security-baseline.md#slice-4-account-controls).

## Boundary 8: Public registries to the running image

| | Threat | State |
| --- | --- | --- |
| T | A malicious dependency or base image | Mitigated. Base image by digest, Python dependencies pinned, actions pinned by SHA, Dependabot proposing bumps on all three |
| T | A malicious bump merged unreviewed | Residual. A Dependabot pull request is still a pull request, and the review is a human reading a diff |
| S | An image that did not come from this pipeline | **Open.** `provenance: false` is set in the build, no SBOM is produced, nothing is signed, and Binary Authorization is not enforced. The only control is that the pipeline identity is the sole writer to the repository, which is an authorization control rather than an attestation |

The last row matters less than it first appears, and the ordering below reflects that. Attestation proves *this pipeline built it*. It says nothing about whether the commit should have been built, which is boundary 5's question and the cheaper one to answer first.

That question is answered, so the last row is accepted for now rather than carried as work in progress. The pipeline identity is the only writer to the registry, the image is pulled by digest, and finding 7 closed the path an unvalidated commit took to get built. Signing and admission enforcement are a phase of their own, and this model is revisited when Phase 16 changes it substantially, so the acceptance is reconsidered there rather than expiring quietly.

Reconsidered once already, on 2026-09-20, against the agent repository and the Phase 19 pull request capability. The acceptance holds, and the reasoning is on [the agent edge](#the-agent-edge-carries-more-than-the-sky-edge).

## Attack paths, ranked

Ranked by likelihood multiplied by impact against the assets above, not by how interesting they are. The ranking is as modelled, before Phase 13; the last column records what has since been put on each path.

| Path | Likelihood | Impact | Net | Control now |
| --- | --- | --- | --- | --- |
| Exhaustion from an unrated public endpoint | Happening continuously | Cost and availability | **Highest** | Rate limiting, 300 a minute per address |
| Account compromise to arbitrary content on the domain | Low | Crown jewel | **High** | MFA and a ruleset that now matches `main`. `sky` still open |
| Certificate issued through the DNS zone | Low | Crown jewel, and invisible from inside the platform | **High** | CAA restricting issuance to `pki.goog`, on a signed zone |
| Downgrade against TLS 1.0 or 1.1 | Low | Low; nothing confidential in transit | Medium, and visibly wrong | TLS 1.2 floor. Closed |
| An upstream commit reaching production unvalidated | Moderate | Depends entirely on the commit | Medium | Upstream CI queried before the pin is proposed |
| RCE in the application | Low | Very low; the Pod is close to inert | **Lowest** | Six overlapping, unchanged |

The shape of that table was the finding. Six overlapping controls sat on the bottom row, and the top three had one, none, and none. Phase 13 put a control on four of the six rows, including the highest ranked, and Phase 14 put one on the third, so every row now carries something. The third is still the weakest, because CAA is enforced by the CA rather than by this platform and the zone is outside both repositories.

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

| # | Boundary | Finding | Proposed response | Status |
| --- | --- | --- | --- | --- |
| 1 | 1 | No rate limiting on the public endpoint | Mitigate | Closed, proven under a flood and isolated at 125 rps. 593 of 1200 requests from one address refused with `429`; at the rate Phase 12d drove unthrottled to 8 of 8 replicas, the throttle held sky to 3 of 8 inside the namespace quota |
| 2 | 4 | Merge review is not a control on the path to Google Cloud | Re-decide with the consequence recorded | Closed. Scoped to `refs/heads/main`, both directions measured: `main` still deploys, a dispatch from another branch is rejected by the attribute condition |
| 3 | 6 | No CAA record, so no CA is excluded from issuing for this domain | Mitigate | Closed. `0 issue "pki.goog"` and `0 issuewild ";"` verified on two public resolvers, with Universal SSL disabled to stop Cloudflare widening the set |
| 4 | 6 | Renewal failure is silent | Mitigate | Closed. `cert-expiry` reads the served certificate and fails below 21 days remaining |
| 5 | 1 | TLS 1.0 and 1.1 accepted; no SSL policy defined | Mitigate | Closed, measured. TLS 1.2 floor, both refused |
| 6 | 1 | No HSTS, and no other response security headers | Mitigate | Closed. HSTS, `nosniff` and `Referrer-Policy` live, and both paths serve a policy: the nginx root's from #100, sky's own once #106 moved the pin |
| 7 | 5 | The pin bump is the one pull request CI does not validate | Mitigate | Closed. Upstream CI is queried before the pin is proposed |
| 8 | 7 | Account controls are assumed, not verified | Verify | Closed. Both assumptions that were wrong are fixed: `k8-lab`'s ruleset matched no branch, and `sky`'s `main` was unprotected |
| 9 | 6 | No DS record, so the zone is unsigned | Decide | Closed. Decided in favour of signing, and signed: DS `2371 13 2`, verified on two resolvers, with the `ad` flag set |
| 10 | 8 | No provenance, SBOM, signature, or admission policy | Mitigate, after 7 | Accepted for now, with the reason on [boundary 8](#boundary-8-public-registries-to-the-running-image). Reconsidered when this model is revisited |
| 11 | 3 | DNS is the one egress channel out of the namespace | Accept | Accepted |
| 12 | 2 | Shared Google ranges admitted by NetworkPolicy | Accept | Accepted |

Findings 1, 3, 5, 6 and 9 are measured rather than reasoned: [the Phase 13 worklog](../worklog/phase-13-security-baseline.md) records every run, and [Phase 14](../worklog/phase-14-close-the-baseline.md) records the runs that closed 1, 3 and 9. Findings 3 and 9 were written here as unverified and might have turned out closed. Both were open when measured, and both are closed now.

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

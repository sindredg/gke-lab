# Worklog: Phase 14 Close the Baseline

Date: 2026-09-17
Status: Partial. Four slices measured, two unmeasured, one finding raised.

## Goal

Close the findings [Phase 13](phase-13-security-baseline.md) measured, in the order the [threat model](../reference/threat-model.md) ranked them. See [Phase 14](../plan.md#phase-14-close-the-baseline).

Four slices have commands and output behind them. Two do not, and are written here as headings with the gap named rather than left out, because a phase that reports only its finished slices reads as complete. The load test in particular is the phase's own exit criterion and it has not been run.

## Slice 1: Federation scoped to refs/heads/main

Status: Complete in the allow direction. The deny direction is untested.

[#102](https://github.com/sindredg/k8-lab/pull/102) narrowed the provider's `attribute_condition` from the repository to the repository and the ref, closing finding 2 on [boundary 4](../reference/threat-model.md#boundary-4-github-actions-to-google-cloud). The reasoning is in [decisions.md](../decisions.md#federation-trust-boundary).

The plan touched one resource, in place, and replaced nothing:

```bash
terraform -chdir=terraform plan
```

```text
  # module.delivery.google_iam_workload_identity_pool_provider.github will be updated in-place
  ~ resource "google_iam_workload_identity_pool_provider" "github" {
      ~ attribute_condition                = "assertion.repository == 'sindredg/k8-lab'" -> "assertion.repository == 'sindredg/k8-lab' && assertion.ref == 'refs/heads/main'"
        id                                 = "projects/example-security-lab/locations/global/workloadIdentityPools/github/providers/github-oidc"
        name                               = "projects/222222222222/locations/global/workloadIdentityPools/github/providers/github-oidc"
        # (9 unchanged attributes hidden)

        # (1 unchanged block hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**The apply's own completion line was not captured and is not reproduced here.** The session ran `apply` against the saved plan and read only the output block that follows it; a second invocation returned `Error: Saved plan is stale`, which is the expected result of a plan already consumed. Convergence is therefore evidenced by the two checks below rather than by an `Apply complete!` line.

The condition that actually landed on the provider:

```bash
gcloud iam workload-identity-pools providers describe github-oidc \
  --location=global --workload-identity-pool=github --format=json
```

```text
{
  "attributeCondition": "assertion.repository == 'sindredg/k8-lab' && assertion.ref == 'refs/heads/main'",
  "attributeMapping": {
    "attribute.ref": "assertion.ref",
    "attribute.repository": "assertion.repository",
    "google.subject": "assertion.sub"
  },
  "displayName": "GitHub OIDC",
  "name": "projects/222222222222/locations/global/workloadIdentityPools/github/providers/github-oidc",
  "oidc": {
    "issuerUri": "https://token.actions.githubusercontent.com"
  },
  "state": "ACTIVE"
}
```

State matches configuration afterwards:

```bash
terraform -chdir=terraform plan -detailed-exitcode
```

```text
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
EXIT=0
```

### Delivery still works

Run [35277444850](https://github.com/sindredg/k8-lab/actions/runs/35277444850), `workflow_dispatch` from `main` with `build_only=true`, conclusion `success`:

```text
1   Set up job                              completed  success
2   Check out this repository               completed  success
3   Read the pinned commit                  completed  success
4   Fetch the application source at the pinned commit  completed  success
5   Authenticate to Google Cloud            completed  success
6   Set up gcloud                           completed  success
7   Authenticate Docker against Artifact Registry      completed  success
8   Set up Buildx                           completed  success
9   Build and push                          completed  success
10  Report the digest                       completed  success
11  Get cluster credentials                 completed  skipped
12  Check the workload exists               completed  skipped
13  Apply the Deployment with the new digest            completed  skipped
14  Wait for the rollout                    completed  skipped
15  Smoke test from inside the cluster      completed  skipped
```

The auth step, which is the one the condition governs:

```text
2026-09-17T21:34:46.9615645Z   workload_identity_provider: projects/222222222222/locations/global/workloadIdentityPools/github/providers/github-oidc
2026-09-17T21:34:46.9616322Z   service_account: k8-lab-deploy@example-security-lab.iam.gserviceaccount.com
2026-09-17T21:34:47.2527109Z Created credentials file at "/home/runner/work/k8-lab/k8-lab/gha-creds-6c6b25e2896b562c.json"
```

Steps 11 to 15 skipped, which is what `build_only` is for. The credentials file was created at 21:34:47Z, after the condition landed.

### Only half the control is verified

This proves a token from `refs/heads/main` is still accepted. **It does not prove a token from any other ref is now rejected**, and that is the direction the finding was about. A provider whose condition silently failed to narrow would produce exactly the output above.

What would settle it: dispatch `Deploy sky` from any branch that is not `main`. The run should fail at step 5, and the failure should name the attribute condition. Until that run exists, the control is half-verified and the threat model should not record boundary 4's finding 2 as closed on the strength of this slice alone.

## Slice 2: Branch protection

Status: Complete. The starting state was misread, and the correction is a finding.

### What was already there

Both repositories answered the classic protection endpoint identically:

```bash
gh api repos/sindredg/k8-lab/branches/main/protection
gh api repos/sindredg/sky/branches/main/protection
```

```text
{"message":"Branch not protected","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"404"}
gh: Branch not protected (HTTP 404)
```

That 404 was read as "nothing is there, in either repository". **For `k8-lab` that reading is wrong**, and [Phase 13](phase-13-security-baseline.md) had already documented why: the repository is governed by a Ruleset, a separate mechanism the classic endpoint does not see. The trap was recorded in this repository's own worklog and walked into anyway.

The ruleset, read this session:

```bash
gh api repos/sindredg/k8-lab/rulesets
```

```text
21742516 Protect main active 2026-08-28T17:16:30.952+02:00 2026-09-17T20:28:40.082+02:00
```

```bash
gh api repos/sindredg/k8-lab/rulesets/21742516
```

```text
{"conditions":{"ref_name":{"exclude":[],"include":["~DEFAULT_BRANCH"]}},"current_user_can_bypass":"never","rules":[{"parameters":null,"type":"deletion"},{"parameters":null,"type":"non_fast_forward"},{"parameters":{"do_not_enforce_on_create":false,"required_status_checks":[{"context":"Terraform","integration_id":15368},{"context":"Kubernetes","integration_id":15368},{"context":"Docs and scripts","integration_id":15368}],"strict_required_status_checks_policy":true},"type":"required_status_checks"},{"parameters":{"allowed_merge_methods":["merge","squash","rebase"],"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_extra_approval_for_unattributed_changes":true,"require_last_push_approval":false,"required_approving_review_count":0,"required_review_thread_resolution":false,"required_reviewers":[]},"type":"pull_request"}],"updated_at":"2026-09-17T20:28:40.082+02:00"}
```

So `k8-lab` already required `Terraform`, `Kubernetes` and `Docs and scripts`, with `strict_required_status_checks_policy: true` and `current_user_can_bypass: "never"`. `Static analysis` was the one missing check, which is what this slice was asked to add.

`sky` has no ruleset, so for `sky` the 404 was the whole truth:

```bash
gh api repos/sindredg/sky/rulesets
```

```text
[]
```

### What was set

Classic branch protection, on both:

```bash
gh api -X PUT repos/sindredg/k8-lab/branches/main/protection --input k8lab-prot.json
```

```text
{"url":"https://api.github.com/repos/sindredg/k8-lab/branches/main/protection","required_status_checks":{"url":"https://api.github.com/repos/sindredg/k8-lab/branches/main/protection/required_status_checks","strict":false,"contexts":["Static analysis"],"contexts_url":"https://api.github.com/repos/sindredg/k8-lab/branches/main/protection/required_status_checks/contexts","checks":[{"context":"Static analysis","app_id":15368}]},"required_signatures":{"url":"https://api.github.com/repos/sindredg/k8-lab/branches/main/protection/required_signatures","enabled":false},"enforce_admins":{"url":"https://api.github.com/repos/sindredg/k8-lab/branches/main/protection/enforce_admins","enabled":false},"required_linear_history":{"enabled":false},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false},"block_creations":{"enabled":false},"required_conversation_resolution":{"enabled":false},"lock_branch":{"enabled":false},"allow_fork_syncing":{"enabled":false}}
```

```bash
gh api -X PUT repos/sindredg/sky/branches/main/protection --input sky-prot.json
```

```text
{"url":"https://api.github.com/repos/sindredg/sky/branches/main/protection","required_status_checks":{"url":"https://api.github.com/repos/sindredg/sky/branches/main/protection/required_status_checks","strict":false,"contexts":["Lint and test","Frontend tests"],"contexts_url":"https://api.github.com/repos/sindredg/sky/branches/main/protection/required_status_checks/contexts","checks":[{"context":"Lint and test","app_id":15368},{"context":"Frontend tests","app_id":15368}]},"required_signatures":{"url":"https://api.github.com/repos/sindredg/sky/branches/main/protection/required_signatures","enabled":false},"enforce_admins":{"url":"https://api.github.com/repos/sindredg/sky/branches/main/protection/enforce_admins","enabled":false},"required_linear_history":{"enabled":false},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false},"block_creations":{"enabled":false},"required_conversation_resolution":{"enabled":false},"lock_branch":{"enabled":false},"allow_fork_syncing":{"enabled":false}}
```

Effective state, read back this session:

| Repo | Mechanism | Required contexts | Strict |
| --- | --- | --- | --- |
| k8-lab | Ruleset 21742516 | `Terraform`, `Kubernetes`, `Docs and scripts` | true |
| k8-lab | Classic protection | `Static analysis` | false |
| sky | Classic protection | `Lint and test`, `Frontend tests` | false |

### Why "Public surface" was left out

`security-scan.yml` triggers on `pull_request` only for two paths:

```yaml
  pull_request:
    branches: [main]
    paths:
      - 'scripts/check-public-surface.sh'
      - '.github/workflows/security-scan.yml'
```

A required context that never reports leaves a pull request pending forever. Any pull request touching neither path would never produce `Public surface`, so requiring it would block every other change in the repository. Left out deliberately, not overlooked.

### Choices, not defaults

- `strict: false` on both classic rules. Chosen, not inherited. The brief was to require a check, not to change merge mechanics. It does **not** weaken anything: `k8-lab`'s ruleset already sets `strict_required_status_checks_policy: true`, and GitHub evaluates rulesets and classic protection together, taking the more restrictive. The up-to-date requirement Phase 13's open question asked about is already enforced on `k8-lab` by the ruleset.
- `enforce_admins: false` on both. Chosen. The sole collaborator is the only identity that can apply infrastructure and merge. With `required_approving_review_count: 0` and no second reviewer, `true` would leave nobody able to merge. The ruleset's `current_user_can_bypass: "never"` is the stronger control on `k8-lab` and is untouched.

### Finding: two mechanisms now govern one branch

`k8-lab`'s `main` is protected by a ruleset **and** by classic protection, with a disjoint set of required checks and disagreeing `strict` settings. Nothing is weaker for it, but the required-check list for the branch is now spread across two API surfaces, and a future reader of either one sees an incomplete answer. This is the same class of problem Phase 13 found, where an active-looking ruleset matched no branch for three weeks.

The cleaner shape is one mechanism: add `Static analysis` to ruleset 21742516's `required_status_checks` and delete the classic rule on `k8-lab`. Not done here, because this session's scope was writing and read-only lookups. `sky` has no ruleset, so classic protection is the whole answer there and needs no consolidation.

## Slice 3: Content Security Policy on the project page

Status: Complete.

[#100](https://github.com/sindredg/k8-lab/pull/100) added the policy. Merging triggered `deploy.yml`. The header as served:

```bash
curl -sS -o /dev/null -D - https://sindrg.com/
```

```text
HTTP/2 200 
server: nginx/1.30.4
date: Thu, 17 Sep 2026 21:35:02 GMT
content-type: text/html
cache-control: no-store
content-security-policy: default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
via: 1.1 google
referrer-policy: strict-origin-when-cross-origin
strict-transport-security: max-age=86400
x-content-type-options: nosniff
alt-svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000
```

That closes the `csp` and `frame-ancestors` findings on the nginx root, and confirms the Phase 13 header set is still present alongside it.

### The page still renders under it

`default-src 'none'` blocks every resource class not named explicitly, so the policy is only safe if the page loads nothing it does not allow. It loads nothing at all:

```bash
grep -c "<script" page.html   # 0
grep -c "<img" page.html      # 0
grep -c "<style" page.html    # 1
curl -sS https://sindrg.com/ | wc -c
```

```text
0
0
1
17149
```

The document is complete, closing tags present:

```text
        </nav>
      </footer>
    </div>
  </body>
</html>
```

Every external reference in the page is an anchor `href`, which no directive in this policy restricts:

```bash
grep -oE '<script[^>]*>|<img[^>]*>|<link[^>]*>|url\([^)]*\)|https?://[^"'"'"' )]*' page.html | sort -u
```

```text
https://github.com/sindredg/k8-lab
https://github.com/sindredg/k8-lab/blob/main/decisions.md
https://github.com/sindredg/k8-lab/tree/main/worklog
```

The single `<style>` block is covered by `style-src 'unsafe-inline'`. `img-src 'self'` is declared and currently unused by any element; it still governs the browser's implicit `/favicon.ico` request, which is same-origin.

## Slice 4: CAA derivation

Status: Derived. **Not applied.** One question unresolved that decides correctness.

Finding: no CAA record, on [boundary 6](../reference/threat-model.md#boundary-6-dns-and-certificate-issuance). Confirmed still absent:

```bash
dig +short CAA sindrg.com @1.1.1.1
dig +noall +answer CAA sindrg.com @8.8.8.8
dig +noall +answer CAA www.sindrg.com @8.8.8.8
```

```text
```

All three returned nothing. Every CA that will issue for this domain is currently permitted.

### The issuer, read off the live certificate

Not taken from configuration or from memory:

```bash
echo | openssl s_client -connect sindrg.com:443 -servername sindrg.com 2>/dev/null |
  openssl x509 -noout -issuer -subject -dates -ext subjectAltName -ext authorityInfoAccess
```

```text
issuer=C = US, O = Google Trust Services, CN = WR3
subject=CN = sindrg.com
notBefore=Sep  4 12:17:24 2026 GMT
notAfter=Dec  3 13:13:19 2026 GMT
X509v3 Subject Alternative Name: 
    DNS:sindrg.com
Authority Information Access: 
    CA Issuers - URI:http://i.pki.goog/wr3.crt
```

The chain as served:

```bash
echo | openssl s_client -connect sindrg.com:443 -servername sindrg.com -showcerts 2>/dev/null |
  grep -E "^ *[0-9]+ s:|^ *i:"
```

```text
 0 s:CN = sindrg.com
   i:C = US, O = Google Trust Services, CN = WR3
 1 s:C = US, O = Google Trust Services, CN = WR3
   i:C = US, O = Google Trust Services LLC, CN = GTS Root R1
 2 s:C = US, O = Google Trust Services LLC, CN = GTS Root R1
   i:C = BE, O = GlobalSign nv-sa, OU = Root CA, CN = GlobalSign Root CA
```

One SAN, no wildcard. Issued by GTS WR3 under GTS Root R1, cross-signed by GlobalSign Root CA.

### The CA identifier

A CAA record names an Issuer Domain Name, which is whatever string the CA declares it honours, not the issuer CN read above. For Google Trust Services that string is **`pki.goog`**, per section 4.2.4 of its Certification Practice Statement v5.22, which states `pki.goog` is the only Issuer Domain Name it recognises in `issue`, `issuewild` or `issuemail` records.

Source: <https://pki.goog/repo/cps/5.22/GTS-CPS.html>

**This one item is not pasted verbatim.** The CPS was read through a page fetch that returned a summary of section 4.2.4 rather than its text, so the sentence above is a paraphrase of that summary and not a quotation. The identifier is corroborated independently by the certificate's own AIA URI, `http://i.pki.goog/wr3.crt`, but the CPS wording should be read directly before the record is created.

### The records proposed

| Name | Flags | Tag | Value |
| --- | --- | --- | --- |
| `sindrg.com` | 0 | `issue` | `pki.goog` |
| `sindrg.com` | 0 | `issuewild` | `;` |

The second row is **required, not optional**. RFC 8659 resolves a wildcard request against `issuewild` when one is present, and falls back to `issue` when none is. With `issue "pki.goog"` alone, a wildcard certificate for `*.sindrg.com` from GTS would still be authorised. The served certificate has a single SAN and the platform issues no wildcard, so `issuewild ";"` — the empty issuer set, meaning no CA may issue a wildcard — costs nothing and is what makes the pair mean "this issuer and nothing else".

Flags `0` rather than `128`: the critical flag changes how a CA must treat a property tag it does not understand, and adds nothing for `issue` and `issuewild`, which every compliant CA understands.

### Not added, and why the next step is not DNS

The record was not created. DNS is not this repository's to change, and one question decides whether the pair above is correct or an outage:

**Is `sindrg.com` proxied through Cloudflare, or is Cloudflare only hosting the zone?** If the zone is DNS-only, the platform's gateway terminates TLS and GTS is the only issuer, so a `pki.goog`-only CAA is right. If the record is proxied, Cloudflare's edge terminates TLS and issues its own certificate through its own CAs, and a `pki.goog`-only CAA would forbid the renewal of the certificate actually facing visitors.

This was not resolved. `dig +short A sindrg.com` compared against the gateway address `8.232.183.150` answers it.

### What breaks if it is wrong

CAA is evaluated by the CA at issuance, not at request time, and the platform renews through Certificate Manager's ACME DNS-01 authorisation. So a wrong record changes nothing visible: the current certificate keeps serving until **2026-12-03**, and the failure appears as an expired certificate on a site that was working the previous day. The failure mode is silent and delayed, which is the same shape as the Cloudflare-versus-Google collision this project already hit at `_acme-challenge`.

## Slice 5: The rate limit under flood

Status: **Not run.** No result exists.

This is Phase 14's exit criterion and the threat model's outstanding claim on [boundary 1](../reference/threat-model.md#boundary-1-internet-to-gateway): the rate limit is recorded as not yet proven under a flood. That claim still has nothing behind it. No load test was run, in this session or the one before it.

### Preconditions, not results

The two figures below were read from the platform before any test and are recorded so a future run has its baseline. **Neither is a measurement of the rate limit.**

The Cloud Armor policy, from `terraform/modules/gateway/main.tf`:

```terraform
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = 300
        interval_sec = 60
      }
    }
```

The namespace quota at rest:

```bash
kubectl get resourcequota -n demo -o wide
```

```text
NAME          REQUEST                                                        LIMIT                                            AGE
demo-budget   pods: 4/16, requests.cpu: 800m/5, requests.memory: 384Mi/2Gi   limits.cpu: 2500m/13, limits.memory: 768Mi/4Gi   19d
```

### The hypothesis

300 requests per 60 seconds per IP is an effective ceiling of 5 rps from one source. If the throttle works, a single address pushed well past that rate should see 429s begin once its first 60-second window is spent, and the backends should never see more than about 5 rps from it. The interesting consequence is the second-order one: the rate limit should keep the namespace clear of its `ResourceQuota`, because the HPA never sees enough traffic to scale toward the cap that Phase 12 filled.

### What would prove it

- A single source held above 300 requests per minute at `sindrg.com`, from the `loadtest/` harness, which is the repo owner's to run.
- The request rate offered, and the point in the run where 429s first appear, against the start of that source's first 60-second window.
- `ResourceQuota` sampled through the run, showing whether `pods`, `requests.cpu` and `limits.cpu` stayed below `demo-budget`. `record.sh` samples this every 5s.
- The uptime check's state across the same window. It probes from Google's prober addresses, each its own source under the per-IP key, so the prediction is that it is unaffected. The availability alert is expected to fire regardless and is not an incident.

Until that run exists, the threat model's wording on boundary 1 should stay as it is.

## Slice 6: Security Command Center

Status: **Not started.**

The question is what the free tier covers for this project today, specifically whether Security Health Analytics configuration scanning is included or whether Google now directs that to Compliance Manager. Nothing was looked up. No answer should be inferred from the tier this project was on when Phase 13 was written.

## What this phase leaves open

| # | Item | State |
| --- | --- | --- |
| 1 | Federation deny direction | Untested. A non-main dispatch would settle it |
| 2 | Rate limit under flood | Not run. Phase 14's exit criterion |
| 3 | Security Command Center tier | Not started |
| 4 | CAA record | Derived, not added. Cloudflare proxy question unresolved |
| 5 | Two protection mechanisms on `k8-lab` main | Consolidate into ruleset 21742516 |

## Where this is recorded elsewhere

The threat model's findings table, `decisions.md` on branch protection, and
Phase 14 in `plan.md` were reconciled against this worklog after it landed.

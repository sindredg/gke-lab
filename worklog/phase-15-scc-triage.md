# Worklog: Phase 15 Security Command Center triage

Date: 2026-09-20
Status: In progress. The notification path is applied. No findings are triaged, and no worker exists.

## Goal

Read the findings Security Command Center has produced since 2026-09-18, correlate them against this repository's own records, and notify through the existing email channel. See [Phase 15](../plan.md#phase-15-security-command-center-triage). The contract the work is held to was settled first, in [#113](https://github.com/sindredg/k8-lab/pull/113).

This worklog covers the infrastructure only. The overlap measurement the exit criteria name is open, both drills are open, and the agent source in [ai-k8s](https://github.com/sindredg/ai-k8s) is empty.

## What the findings look like before anything reads them

Read at project scope, filtered on state, because an earlier read that ignored state counted four retired findings as live:

```bash
gcloud scc findings list projects/222222222222 --location=global \
  --format='value(finding.state,finding.category,finding.eventTime)' \
  | grep -viE 'SOFTWARE_|OS_VULN' | sort
```

```text
ACTIVE    BINARY_AUTHORIZATION_DISABLED          2026-09-19T22:05:22Z
ACTIVE    CLUSTER_SECRETS_ENCRYPTION_DISABLED    2026-09-19T22:05:22Z
ACTIVE    EXTERNALLY_EXPOSED_SERVICE_VIA_LOAD_BALANCER  2026-09-19T03:51:40Z
ACTIVE    EXTERNALLY_EXPOSED_SERVICE_VIA_LOAD_BALANCER  2026-09-19T03:51:40Z
ACTIVE    INTRANODE_VISIBILITY_DISABLED          2026-09-19T22:05:22Z
ACTIVE    MASTER_AUTHORIZED_NETWORKS_DISABLED    2026-09-19T22:05:22Z
ACTIVE    NON_ORG_IAM_MEMBER                     2026-09-19T00:13:03Z
ACTIVE    PRIMITIVE_ROLES_USED                   2026-09-19T00:13:03Z
INACTIVE  FIREWALL_RULE_LOGGING_DISABLED         2026-09-18T17:27:04Z
INACTIVE  FLOW_LOGS_DISABLED                     2026-09-18T17:27:22Z
INACTIVE  PRIVATE_GOOGLE_ACCESS_DISABLED         2026-09-18T17:27:22Z
INACTIVE  PUBLIC_IP_ADDRESS                      2026-09-18T17:26:56Z
```

Six active misconfigurations, two external exposures, one threat finding, and 653 vulnerability findings not shown. The four `INACTIVE` ones all name `loadgen` resources in `europe-west4`. Security Command Center raised them at 17:02 on 2026-09-18 and retired them at 17:27, when the load generator and its VPC were deleted, which is the cost posture being honoured and the detector tracking it. They are kept here because they are the proof that one finding produces more than one event, which is why the worker keys on state as well as event time.

## The overlap, read by hand

Not the measurement the exit criteria ask for. That one is produced by the worker with provenance. This is the hand check that says whether the phase is pointed at anything real.

```bash
grep -rn "CKV_GCP_13\"\|CKV_GCP_20\"\|CKV_GCP_61\"\|CKV_GCP_65\"\|CKV_GCP_66\"" \
  ~/.local/share/pipx/venvs/checkov/lib/python3.12/site-packages/checkov/terraform/checks/
```

```text
GKEClientCertificateDisabled.py:8:        id = "CKV_GCP_13"
GKEMasterAuthorizedNetworksEnabled.py:9:  id = "CKV_GCP_20"
GKEEnableVPCFlowLogs.py:10:               id = "CKV_GCP_61"
GKEBinaryAuthorization.py:8:              id = "CKV_GCP_66"
GKEKubernetesRBACGoogleGroups.py:9:       id = "CKV_GCP_65"
```

| Active finding | Priced in `.checkov.baseline` |
| --- | --- |
| `MASTER_AUTHORIZED_NETWORKS_DISABLED` | Yes, `CKV_GCP_20` |
| `BINARY_AUTHORIZATION_DISABLED` | Yes, `CKV_GCP_66`, and threat model finding 10 |
| `CLUSTER_SECRETS_ENCRYPTION_DISABLED` | No |
| `INTRANODE_VISIBILITY_DISABLED` | No |
| `NON_ORG_IAM_MEMBER` | No |
| `PRIMITIVE_ROLES_USED` | No |

Two of six. [Phase 14](phase-14-close-the-baseline.md) expected high overlap and wrote that its value would be "the remainder plus the threat detection nothing else here provides". The remainder is two thirds.

Worth recording how this was nearly got wrong. A first pass paired `CLUSTER_SECRETS_ENCRYPTION_DISABLED` with `CKV_GCP_65` and `INTRANODE_VISIBILITY_DISABLED` with `CKV_GCP_61` on the strength of the names, and reported four of six. `CKV_GCP_65` is RBAC Google Groups and `CKV_GCP_61` is VPC flow logs. Neither pairing exists. That error is why the contract in [#113](https://github.com/sindredg/k8-lab/pull/113) requires every verdict to cite a corpus entry and requires the worker to resolve the citation before accepting the verdict.

## Slice 1: The certificate that was nearly replaced

Status: Closed. The cause is removed and a guard is in place.

`terraform apply` planned `7 to add, 1 to change, 1 to destroy`. The destroy was the certificate serving the public domain. It failed:

```text
Error: Error when reading or editing Certificate: googleapi: Error 400: can't
delete certificate that is referenced by a CertificateMapEntry or other resources
    "subject": "projects/222222222222/locations/global/certificates/k8-lab-gateway-cert",
    "type": "RESOURCE_STILL_IN_USE"
```

![Certificate Manager refusing the delete](../images/phase15-certificate-destroy-refused.png)

Nothing was destroyed and nothing was created; the apply stopped on its first operation. The site never stopped serving:

```bash
curl -sS -o /dev/null -w "HTTP %{http_code}\n" https://sindrg.com/healthz
```

```text
HTTP 200
```

The cause was four API names. `module.gateway` carries `depends_on = [google_project_service.required]`. This phase added `aiplatform`, `pubsub`, `securitycenter` and `storage` to that set, so the module depended on a resource with pending changes, so Terraform deferred reading `data.google_project.this` until apply, so `.number` was unknown at plan time. It is interpolated into `dns_authorizations`, which is `ForceNew`:

```hcl
dns_authorizations = [
  "projects/${data.google_project.this.number}/locations/global/dnsAuthorizations/...",
]
```

The project number is a constant and was identical before and after. Terraform could not prove that, so it planned a replacement. Any edit to `required_services` by anyone would have done the same.

The fix passes the number in as a variable, so it is known at plan time, and removes the data source in both the gateway module and the new findings module, which had the same pattern waiting on its IAM members. After it:

```text
Plan: 6 to add, 0 to change, 0 to destroy.
```

Only Certificate Manager's own refusal stopped this, which is luck rather than a control, so the certificate now carries `prevent_destroy`. A replacement has to be a deliberate act.

## Slice 2: The alert filter that could not be left open

Status: Closed, and a decision recorded in the plan was wrong.

The alert policy was written with no `resource.type` clause, deliberately. The reasoning was that no worker had written a log entry yet, so naming the type would be a guess, and a wrong guess fails silently. Cloud Monitoring does not allow the choice:

```text
Error: Error creating AlertPolicy: googleapi: Error 400: Field
alert_policy.conditions[0].condition_threshold.filter had an invalid value of
"metric.type = "logging.googleapis.com/user/triage/verdicts"": must specify a
restriction on "resource.type" in the filter
```

![Cloud Monitoring rejecting a filter with no resource type](../images/phase15-alert-policy-resource-type.png)

`k8s_container` is therefore a contract rather than an observation, and the worker has to set that monitored resource explicitly rather than relying on client library detection.

That contract is measurable now, before the worker exists:

```bash
gcloud logging write triage-verdict \
  '{"verdict":"new","finding":{"category":"PROBE","severity":"LOW"}}' \
  --payload-type=json --severity=WARNING
```

![Writing a verdict shaped log entry by hand](../images/phase15-logging-probe.png)

```bash
gcloud logging read 'logName="projects/example-security-lab/logs/triage-verdict"' \
  --limit=1 --format='value(resource.type,jsonPayload.verdict)'
```

```text
global	new
```

A hand written entry lands as `global`. The metric counted it, because the metric filters on `logName` and the verdict only. The alert did not fire, because the alert requires `k8s_container`. So a worker that writes the wrong monitored resource is counted and never paged, which is the silent failure the original reasoning was trying to avoid and the filter now makes explicit.

## What is applied

```bash
terraform -chdir=terraform plan -detailed-exitcode; echo "EXIT=$?"
```

```text
No changes. Your infrastructure matches the configuration.
EXIT=0
```

![Apply converged](../images/phase15-apply-converged.png)

Read back from the API rather than from state:

```bash
gcloud alpha monitoring policies list \
  --filter='displayName:(Security finding needs a decision)' \
  --format='value(displayName,enabled,notificationChannels)'
gcloud alpha monitoring channels list --format='value(displayName,type)'
gcloud logging metrics describe triage/verdicts --format='value(name,filter)'
```

```text
Security finding needs a decision	True	projects/example-security-lab/notificationChannels/5886169687490354841
Platform owner	email
triage/verdicts	logName = "projects/example-security-lab/logs/triage-verdict" AND jsonPayload.verdict != "accepted"
```

One notification channel, which is the requirement: verdicts reach the address the availability alert already uses, rather than a second one.

## What is proven and what is not

| Claim | State |
| --- | --- |
| Four APIs enabled, metric and alert policy applied | Proven, read back from the API |
| Verdicts reach the existing email channel and no second channel exists | Partly. The channel and policy exist. No verdict has travelled the path |
| `k8s_container` is required, and the wrong resource type fails silently | Proven, by writing an entry that landed as `global` |
| A replacement of the public certificate cannot happen as a side effect | Proven for the cause found, and guarded by `prevent_destroy` |
| Findings reach the cluster | Not started. The topic, subscription, bucket and notification config are written but not wired into the root |
| The overlap is measured with provenance | Open. Two of six by hand, which is not the measurement the exit criteria ask for |
| A finding arriving while the worker is stopped is triaged afterwards | Open, and there is no worker |
| A finding carrying an instruction is triaged to the same verdict | Open |

The percentages Security Command Center reports against compliance standards were read on this date and are deliberately not recorded here. They are computed from the same detectors as the findings above, over a project with one cluster, two stateless workloads and no data, so a high score measures how little applies rather than how much is controlled. Recording it without that framing would be the kind of claim this repository exists to avoid.

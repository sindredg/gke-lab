# Triage worker

How the Phase 15 worker turns a Security Command Center finding into a verdict, and where the model fits.

State on 2026-09-21: running `ai-k8s` [`7135820`](https://github.com/sindredg/ai-k8s/tree/7135820), image `sha256:dff5c0bb`, with `-model=gemini-2.5-flash`. Evidence is in [the Phase 15 worklog](../worklog/phase-15-scc-triage.md).

## The path

```mermaid
flowchart LR
    SCC["Security Command Center<br/>detectors"] --> NC["Notification config<br/>k8-lab-triage"]
    NC --> Topic["Pub/Sub topic<br/>scc-findings"]
    Topic --> Sub["Subscription<br/>scc-triage"]
    Sub --> Worker["triage-worker<br/>agents namespace"]
    Worker --> Ledger[("Ledger bucket<br/>k8-lab-verdicts")]
    Worker -. "unmatched only" .-> Vertex["Vertex AI<br/>gemini-2.5-flash"]
    Worker --> Log["Log entry<br/>triage-verdict"]
    Log --> Metric["Metric<br/>triage/verdicts"]
    Metric --> Alert["Alert policy"]
    Alert --> Mail(["Platform owner email"])
    Sub -- "5 failed deliveries" --> Dead["scc-findings-dead"]
    Dead -. "dead-letter alert" .-> Mail
```

Security Command Center publishes changes, not state. A finding that has not changed since the worker started never reaches it. Changing a finding, even by muting it, publishes it again.

## One message

```mermaid
flowchart TB
    M["Message pulled"] --> P{"Parses and<br/>has a key?"}
    P -- no --> Nack1["Nack, dead letter"]
    P -- yes --> V{"Vulnerability?"}
    V -- yes --> Skip["Count, ack"]
    V -- no --> R{"Already in<br/>the ledger?"}
    R -- "acknowledged" --> Drop["Ack, nothing written"]
    R -- "no, or partway" --> Rules{"Reviewed pairing for<br/>category + resource?"}
    Rules -- yes --> Acc["accepted<br/>settled by rules"]
    Rules -- no --> Model{"Model on and<br/>finding complete?"}
    Model -- no --> New["new<br/>settled by rules"]
    Model -- yes --> Ask["Ask the model<br/>and check the answer"]
    Ask --> Write["Write received, classified"]
    Acc --> Write
    New --> Write
    Write --> N{"accepted?"}
    N -- yes --> Ack["Ack, write acknowledged"]
    N -- no --> Notify["Write notification_attempted,<br/>emit the log entry"]
    Notify --> Ack
```

The order is fixed by [triage idempotency](../decisions.md#triage-idempotency): record before notifying, notify before acknowledging. A crash anywhere repeats work and never loses a finding.

## Who decides what

| Decision | Made by | Why not the model |
| --- | --- | --- |
| Whether a finding is `accepted` | The reviewed pairing in `mapping.yaml` | Acceptance is the quiet path. A model pairs findings to decisions by name, and did so wrongly twice while this phase was drafted |
| `new` versus `insufficient_evidence` for a finding missing a field | The worker | The boundary cannot drift if the model does not hold it |
| Whether a citation is real | Exact lookup in the compiled corpus | Injected text cannot create a corpus entry |
| Budget, spend ceiling, retries, notification | The worker | The model owns no delivery semantics |
| `new`, `contradicts_decision` or `insufficient_evidence` for an unmatched finding, and the explanation | The model | This is the judgement the rules cannot make |

Recorded in [model scope](../decisions.md#model-scope).

## The model call

| | |
| --- | --- |
| Sees | One finding the rules did not match, as escaped JSON, and all 134 corpus entries as id and summary |
| May return | `new`, `contradicts_decision`, `insufficient_evidence` |
| Never returns | `accepted`. It is absent from the schema, refused by the worker, and rejected by the validator |
| Tools | None declared. A tool call in the reply is rejected |
| Parameters | Temperature 0, thinking off, output constrained to a JSON schema |
| Input budget | 16384 tokens, estimated before the call. Over it is refused, never truncated |
| Output budget | 1024 tokens. A reply cut off at the limit is rejected |
| Spend ceiling | 1.00 USD a UTC day. Each call reserves its worst case in the ledger bucket first, so the ceiling survives restarts |
| Timeout | 30 s. A timeout is an error, not a verdict |
| Typical call | About 8900 tokens in, 100 out, 0.003 USD, 1.2 s |
| Repeatability | Not guaranteed. On identical input one borderline verdict flipped between runs, see [slice 12](../worklog/phase-15-scc-triage.md#temperature-0-does-not-fix-the-verdict) |

A reply is refused as `insufficient_evidence`, naming the reason, when it does not decode strictly, cites an id that does not resolve, calls `new` something it also cites, or returns `accepted`. The refusal is still a verdict and still notifies. Every model verdict records the model, parameters, prompt digest, tokens and estimated cost, on the ledger record and as labels on the log entry.

## When something fails

| Failure | What happens | Proven |
| --- | --- | --- |
| Ledger write refused | Nothing classified or notified, message nacked | [Slice 8](../worklog/phase-15-scc-triage.md#a-ledger-write-failure-made-to-happen) |
| Model timeout or 403 | Nothing written, message nacked | [Slice 11](../worklog/phase-15-scc-triage.md#a-failed-call-leaves-nothing-behind) |
| Five failed deliveries | Parked on `scc-findings-dead-sub`, body intact, alert fires | [Slice 11](../worklog/phase-15-scc-triage.md#a-failed-call-leaves-nothing-behind) |
| Worker killed mid-message | Redelivered, resumed from the furthest ledger state | [Slice 7](../worklog/phase-15-scc-triage.md#slice-7-the-crash-boundaries-drilled) |
| Worker stopped | Messages wait on the subscription and are triaged on restart | [Slice 7](../worklog/phase-15-scc-triage.md#a-finding-that-arrives-while-the-worker-is-stopped) |
| Instruction inside a finding | Same verdict as without it | [Slice 11](../worklog/phase-15-scc-triage.md#the-injection) |

A parked finding is not retried. Fix the cause, then mute and unmute the finding to publish it again.

## Identity

The worker runs as `k8-lab-triage@`, through Workload Identity, with no key. Recorded in [agent permission boundary](../decisions.md#agent-permission-boundary).

| Grant | Scope | Allows |
| --- | --- | --- |
| `roles/pubsub.subscriber` | `scc-triage` only | Pull and acknowledge |
| `k8_lab_ledger_appender` | The ledger bucket | Create, read, list. No delete, so no overwrite |
| `k8_lab_model_invoker` | The project | `aiplatform.endpoints.predict` only |
| `roles/logging.logWriter` | The project | Write log entries |

It holds no Security Command Center permission and no cluster credential.

## Where to look

| What | Where |
| --- | --- |
| Verdicts, with reasoning and cost | [Logs Explorer, `triage-verdict`](https://console.cloud.google.com/logs/query;query=logName%3D%22projects%2Fexample-security-lab%2Flogs%2Ftriage-verdict%22?project=example-security-lab) |
| The worker's own log and counters | `kubectl logs -n agents deploy/triage-worker` |
| Model traffic, errors, latency | [Vertex AI API metrics](https://console.cloud.google.com/apis/api/aiplatform.googleapis.com/metrics?project=example-security-lab) |
| The ledger and spend reservations | [Ledger bucket](https://console.cloud.google.com/storage/browser/k8-lab-verdicts-example-security-lab?project=example-security-lab) |
| Parked findings | `gcloud pubsub subscriptions pull scc-findings-dead-sub --limit=10` |
| Alerts | [Monitoring incidents](https://console.cloud.google.com/monitoring/alerting/incidents?project=example-security-lab) |

Vertex AI's Model Registry and Endpoints stay empty. The worker calls Google's hosted model and deploys none.

## Code and records

| | |
| --- | --- |
| Per-message state machine | [`internal/worker/worker.go`](https://github.com/sindredg/ai-k8s/blob/7135820/internal/worker/worker.go) |
| The model call and its checks | [`internal/model/settle.go`](https://github.com/sindredg/ai-k8s/blob/7135820/internal/model/settle.go), [`model.go`](https://github.com/sindredg/ai-k8s/blob/7135820/internal/model/model.go) |
| Spend ceiling | [`internal/model/spend.go`](https://github.com/sindredg/ai-k8s/blob/7135820/internal/model/spend.go) |
| Vertex AI adapter | [`internal/gcp/vertex.go`](https://github.com/sindredg/ai-k8s/blob/7135820/internal/gcp/vertex.go) |
| Verdict contract and validator | [`internal/verdict/record.go`](https://github.com/sindredg/ai-k8s/blob/7135820/internal/verdict/record.go) |
| Reviewed pairings | [`corpus/mapping.yaml`](https://github.com/sindredg/ai-k8s/blob/7135820/corpus/mapping.yaml) |
| Deployment | [`kubernetes/agents/deployment.yml`](../kubernetes/agents/deployment.yml) |
| Infrastructure | [`findings`](../terraform/modules/findings/main.tf), [`agent-identity`](../terraform/modules/agent-identity/main.tf), [`triage.tf`](../terraform/modules/observability/triage.tf) |
| Decisions | [Verdict record](../decisions.md#triage-verdict-record), [model scope](../decisions.md#model-scope), [vulnerability scope](../decisions.md#vulnerability-scope), [backfill](../decisions.md#triage-backfill), [inference provider](../decisions.md#inference-provider) |

# Worklog: Phase 8 Observability and Evidence

Date: 2026-09-06  
Status: Complete.

## Goal

Make platform health observable and provable:

- One dashboard that answers what is wrong.
- One alert that fires when the site stops serving.
- Recorded deployment and cost numbers, to close Milestone 1.

The drills that exercise this signal path are [Phase 10](phase-10-failure-drills.md).

## Problem: an alert on served traffic needs served traffic

This platform has close to no organic traffic, so a condition on the load balancer's 5xx ratio evaluates an empty series during an outage and stays silent. A flat line is indistinguishable from a quiet night. A Cloud Monitoring uptime check supplies its own traffic: a request from outside Google's network, on a fixed period, whose result is the metric.

| Vantage point | Answers | Covers |
| --- | --- | --- |
| Uptime check, from outside | Is the site up for a user? | DNS, certificate, load balancer, HTTPRoute, NetworkPolicy, Pods |
| Load balancer metrics | Which half is broken? | Frontend against backend, response classes, latency |
| Kubernetes metrics and logs | Why? | Restarts, limit pressure, container output |

Only the uptime check pages. The other two are diagnosis.

## Slice 1: Declare the telemetry

Status: Complete

### Changes

- `logging_config`: `SYSTEM_COMPONENTS` and `WORKLOADS`.
- `monitoring_config`: `SYSTEM_COMPONENTS`, with Managed Service for Prometheus.
- Control plane streams left off: `API_SERVER`, `SCHEDULER` and `CONTROLLER_MANAGER` answer "who changed this object", and are noisy and billable for everything else.

Container stdout is the largest ingest line on a cluster this size and Cloud Logging bills it, so keeping `WORKLOADS` is a cost decision rather than a free one.

```bash
terraform -chdir=terraform plan
```

![Four resources to add and one to change](../images/observability-plan.png)

Result: not a no-op. Both blocks were meant to describe behaviour GKE already ran by default, but the plan proposed a cluster change. The assumed default was not the configured state.

## Slice 2: Uptime check, notification channel, and one alert

Status: Complete

### Changes

- A `terraform/modules/observability` module holding the whole signal path.
- An HTTPS uptime check against `/healthz` from three prober regions, every 60 seconds.
- A content matcher requiring `ok`, so a 200 from something that is not this workload still fails.
- `validate_ssl`, making the check an expiry alarm for the managed certificate as well.
- An email notification channel, and one alert policy that opens an incident only when more than one checker location is failing.

`/healthz` rather than `/`, because the page content changes and the health endpoint is a contract. `access_log` is off for that path, so a request every minute adds nothing to log ingest.

```bash
terraform -chdir=terraform apply
```

![Four added, one changed, none destroyed](../images/observability-apply-complete.png)

```bash
gcloud monitoring uptime list-configs
```

![The check, its content matcher, and its TLS validation](../images/observability-uptime-check.png)

Result: `STATIC_IP_CHECKERS` against `https://sindrg.com/healthz`, accepting `STATUS_CLASS_2XX`, matching `ok` in the body, validating the certificate.

![The policy enabled in the console](../images/observability-alert-policy.png)

### Alert tuning

| Setting | Value | Reason |
| --- | --- | --- |
| Locations failing | more than 1 | one failing location is a network path on the internet, not an outage |
| `auto_close` | 30 minutes | the default of 7 days leaves a recovered incident open when the next one arrives |
| Documentation body | the first commands to run | the notification carries the start of the diagnosis, Pods outwards to the edge |

Requiring two locations costs nothing in detection here: one zonal cluster behind one global load balancer has no partial-failure mode, so a real outage fails every location inside the same check period.

## Slice 3: One dashboard, as code

Status: Complete

### Changes

- A `google_monitoring_dashboard` built from a template file, so the layout is reviewable and the console is not the source of truth.
- Panels ordered the way they are read during an incident: is the site up, is traffic arriving and in what class, is latency degrading, did the load balancer or the Pods fail, are containers restarting, what do the warnings say.

![The dashboard taking data](../images/observability-dashboard.png)

| Panel | Reading |
| --- | --- |
| Uptime | 100% |
| Edge and backend traffic | agree on the same traffic |
| p50 and p95 | track each other, a few hundred milliseconds |
| `300` class | the HTTP to HTTPS redirect from Phase 7, not an error |

Nearly all of that traffic is the uptime check itself: without it the panels would be empty, and an outage would look like a quiet night.

### Deliberate omissions

- **No ready-replicas panel.** It needs kube-state-metrics, an exporter with Pod Security and NetworkPolicy consequences in a namespace that enforces `restricted`. Restart count and backend responses answer this phase's questions.
- **Console autosave is on.** Edits made there are silently overwritten by the next `terraform apply`. To keep one: `gcloud monitoring dashboards describe <id> --format=json`.

## Slice 4: The numbers

Status: Complete

### Deployment

Twelve successful pipeline runs.

| | Duration |
| --- | --- |
| Fastest | 58s |
| Median | 70.5s |
| Slowest | 88s |

Commit to serving, measured on run `34692269773`, which sits on the median at 71s.

| Milestone | Time (UTC) | From merge |
| --- | --- | --- |
| Pull request merged | 11:54:51 | |
| Workflow starts | 11:54:53 | 2s |
| Deployment applied | 11:55:35 | 44s |
| Workload Ready | 11:55:50 | 59s |
| Smoke test passes | 11:55:57 | 66s |

| Step | Duration |
| --- | --- |
| Build and push | 12s |
| Apply the Deployment with the new digest | 7s |
| Wait for the rollout | 15s |
| Smoke test from inside the cluster | 7s |

That run carried a configuration change to `app/default.conf.template`, so it is also the measurement for time from a configuration change to a Ready workload: 59 seconds. Roughly half of a deploy is runner setup and authentication, not this platform.

### Cost

Seven days, grouped by SKU. Usage cost, before credits.

| SKU | Usage cost | Share |
| --- | --- | --- |
| Zonal Kubernetes Clusters | kr152.58 | 33% |
| E2 instance core | kr118.68 | 26% |
| E2 instance RAM | kr63.61 | 14% |
| Cloud Load Balancer forwarding rule | kr38.14 | 8% |
| Container images scanned | kr33.95 | 7% |
| Balanced PD capacity | kr18.89 | 4% |
| Private Service Connect endpoint | kr15.26 | 3% |
| Cloud NAT, IP and gateway | kr11.09 | 2% |
| Network Intelligence Center | kr7.83 | 2% |
| Prometheus samples ingested | kr1.78 | 0.4% |

Total kr461.81 for the week, kr0.00 after credits.

| Reading | Value |
| --- | --- |
| Cluster management fee | 33% |
| Nodes, including disk | 44% |
| Reaching the internet | 13% |
| Observability | under 1% |

Three things the total alone would have hidden:

- **The control plane costs more than either node.** A zonal cluster still carries a management fee, and at this size it is the single largest line.
- **Observability is close to free.** Container stdout was expected to dominate ingest. It does not appear at all, and Prometheus samples cost kr1.78 against 3.18 million of them.
- **Image scanning is not free.** kr33.95 across 14 scans, about kr2.43 each. Every pipeline run buys one, including the deliberately broken image from [Phase 10](phase-10-failure-drills.md).

Credits cover the whole bill, so the number to watch is usage cost rather than the subtotal.

## Result

Every claim in this milestone has recorded commands, results and evidence.

| Claim | Evidence |
| --- | --- |
| Onboarding is repeatable | Slice 4: 59s from merge to Ready workload |
| Quotas work | [Phase 4](phase-04-workload-guardrails.md) |
| Pod Security works | [Phase 4](phase-04-workload-guardrails.md) |
| Network isolation works | [Phase 4](phase-04-workload-guardrails.md) |
| Delivery is keyless | [Phase 6](phase-06-keyless-delivery.md) |
| Rollout is controlled | [Phase 10](phase-10-failure-drills.md) |
| Monitoring works | [Phase 10](phase-10-failure-drills.md) |
| Cost is understood | Slice 4: kr461.81 a week, three sources named |

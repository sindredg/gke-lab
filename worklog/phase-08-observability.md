# Worklog: Phase 8 Observability and Evidence

Date: 2026-09-06, drill run 2026-09-12  
Status: in progress. The signal path and the dashboard are built and taking data. The availability drill is run and recorded. The rollout drill, the numbers and the cost snapshot are outstanding.

## Goal

Make platform health observable and provable:

- One dashboard that answers what is wrong.
- One alert that fires when the site stops serving.
- Recorded failure, recovery and cost numbers, to close Milestone 1.

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

## Slice 4: Break it on purpose

Status: availability drill complete. Rollout drill not started.

Scale to zero rather than removing the Gateway or the DNS record. Recovery from those waits on certificate issuance and DNS propagation, which tests Google's provisioning rather than this platform.

### Drill A: availability

Baseline. Four Pods Ready, one of each workload per node.

![Four Pods Running across two nodes](../images/drill-availability-baseline.png)

A probe against the public edge every 10 seconds, stamped in UTC. This is the outage clock.

![The probe loop returning 200](../images/drill-availability-probe-start.png)

```bash
date -u; kubectl scale deployment/nginx -n demo --replicas=0
```

![Scaled to zero at 10:03:45 UTC](../images/drill-availability-scale-zero.png)

The edge failed 6 seconds later.

![200 at 10:03:40, then 503 from 10:03:51](../images/drill-availability-first-503.png)

`sky` kept running, so `/sky`, `/api` and `/static` kept serving. The outage was scoped to `/`.

![Only sky Pods left, and an EndpointSlice with no endpoints](../images/drill-availability-no-endpoints.png)

The empty EndpointSlice is what the edge is reporting. It returns 503 rather than 502, because the backend service has no healthy backend to forward to.

![HTTP/2 503 from the edge](../images/drill-availability-edge-503.png)

Restore.

```bash
date -u; kubectl scale deployment/nginx -n demo --replicas=2
kubectl rollout status deployment/nginx -n demo
```

![Scaled to two at 10:06:54 UTC, rollout successful](../images/drill-availability-restore.png)

The edge recovered 16 seconds after the restore.

![503 through 10:06:58, then 200 from 10:07:10](../images/drill-availability-probe-recovery.png)

![Both endpoints back on port 8080, Pods 55s old, one per node](../images/drill-availability-endpoints-restored.png)

![HTTP/2 200 and a body of ok](../images/drill-availability-edge-200.png)

The uptime check recorded the dip, bottoming out at 45.24% of checks passing.

![The uptime panel dipping to 45.24%](../images/drill-availability-uptime-dip.png)

The alert fired.

![Alert firing, Critical, start time 10:07 AM UTC](../images/drill-availability-alert-email.png)

### Timeline

| Time (UTC) | Event | Source |
| --- | --- | --- |
| 10:03:40 | Last passing probe | probe loop |
| 10:03:45 | `nginx` scaled to zero | `date -u` beside the command |
| 10:03:51 | Edge returns 503 | probe loop |
| 10:06:54 | `nginx` scaled back to two | `date -u` beside the command |
| 10:07:10 | Edge returns 200 | probe loop |
| 10:07 | Alert opens | notification email |

| Interval | Duration |
| --- | --- |
| Scale to zero, to first 503 | 6s |
| Outage at the edge | 3m19s |
| Restore, to first 200 | 16s |
| Scale to zero, to alert | about 3m15s |

### Result: the alert fired after the site was already back

The edge recovered at 10:07:10. The notification start time is 10:07.

Detection took about 3m15s against an outage of 3m19s. The alert was correct and it arrived too late to act on.

The floor is structural rather than a tuning mistake:

- The uptime check runs every 60 seconds per location.
- The condition needs more than one location failing.
- `duration` holds the condition for a further 60 seconds.

Nothing shorter than roughly 3 minutes can open an incident, whatever the alignment period is set to.

This is the intended trade. A blip under 3 minutes is not worth paging, and requiring two locations is what stops one bad network path from waking anyone. The number is recorded here rather than discovered during a real incident.

### Drill B: failed rollout

Status: not started.

| Step | Expected result |
| --- | --- |
| Ship a broken `/healthz` through the pipeline | the surge Pod never passes readiness |
| Let the rollout fail | `Wait for the rollout` times out at 180s, before the smoke test |
| Restore the previous version | the alert stays silent, because `maxUnavailable: 0` keeps the previous digest serving |

Evidence to capture: the failed workflow step, the old Pods still Ready beside the new one that is not, and the uptime panel flat across the same window.
## Slice 5: The numbers

Status: Not started

- Median deploy duration and the per-step split, plus commit to serving.
- Time from a configuration change to a Ready workload.
- A billing snapshot grouped by SKU, with the main cost sources named rather than only the total.

Evidence: the workflow run list with its step timings, and the billing report grouped by SKU.

## Slice 6: Close Milestone 1

Status: Not started

Fill every row of the claim table with a link to its evidence, mark the phase complete, and update the README status and capability table.

## Next

Run the rollout drill: ship a broken `/healthz` through the pipeline and record the uptime panel staying flat while the rollout fails.

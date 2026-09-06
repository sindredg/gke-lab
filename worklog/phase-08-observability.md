# Worklog: Phase 8 Observability and Evidence

Date: 2026-09-06  
Status: In progress. The signal path and the dashboard are built and taking data; the failure drills and the cost snapshot have not been run.

## Goal

Make the platform's health observable and provable: one dashboard that answers what is wrong, one alert that fires when the site stops serving, and the recorded failure, recovery and cost numbers that close Milestone 1.

## The idea the phase turns on

An availability alert built on served traffic only fires when there is served traffic.

This platform has close to no organic traffic. If both Pods die at three in the morning, a condition on the load balancer's 5xx ratio evaluates an empty series, and stays silent. The dashboard shows a flat line, which looks exactly like a healthy quiet night. "No data" is not "no problem", but a threshold cannot tell them apart.

So the alert cannot wait for a visitor. The platform has to produce the traffic it alerts on, which is what a Cloud Monitoring uptime check is: a request from outside Google's network, on a fixed period, whose result is itself the metric. The check is both the load and the signal.

That also settles where to measure, and the vantage point decides what the alert can see:

| Vantage point | Question it answers | Covers |
| --- | --- | --- |
| Uptime check, from outside | Is the site up for a user? | DNS, certificate, load balancer, HTTPRoute, NetworkPolicy, Pods |
| Load balancer metrics | Which half is broken? | Frontend against backend, response classes, latency |
| Kubernetes metrics and logs | Why? | Restarts, limit pressure, container output |

Only the first one pages. The other two are diagnosis, and diagnosis does not need to wake anyone.

## Slice 1: Declare the telemetry that was already running

Status: Complete

### Implemented

- Added `logging_config` with `SYSTEM_COMPONENTS` and `WORKLOADS` to the cluster.
- Added `monitoring_config` with `SYSTEM_COMPONENTS` and Managed Service for Prometheus enabled.
- Left the control plane components off: `API_SERVER`, `SCHEDULER` and `CONTROLLER_MANAGER` answer "who changed this object", and are noisy and billable for everything else.

Container stdout is the largest ingest line on a cluster this size and Cloud Logging bills it, so keeping `WORKLOADS` is a cost decision rather than a free one. The billing snapshot later in this phase is where that shows up.

### The declaration was not a no-op

```bash
terraform -chdir=terraform plan
```

![Four resources to add and one to change](../images/observability-plan.png)

The expectation was an empty diff on the cluster, since both blocks were meant to describe behaviour GKE was already running by default. The plan proposed a change to it instead, which is the plan doing its job: the assumed default was not the configured state. Writing the telemetry scope down turned an inherited setting into a recorded one, and the diff is the evidence that it had never actually been chosen.

## Slice 2: Uptime check, notification channel, and one alert

Status: Complete

### Implemented

- Added a `terraform/modules/observability` module holding the whole signal path.
- An HTTPS uptime check against `/healthz` from three of Google's prober regions, every 60 seconds.
- A content matcher requiring `ok` in the body, so a 200 from something that is not this workload still fails.
- `validate_ssl`, which makes the check an expiry alarm for the managed certificate as well. That certificate renews unattended, so nothing else would notice.
- An email notification channel, and one alert policy that opens an incident only when more than one checker location is failing.

`/healthz` rather than `/`, because the page content changes and the health endpoint is a contract. `access_log` is off for that path, so a request every minute adds nothing to the log ingest Slice 1 just made an explicit cost.

### Applied

```bash
terraform -chdir=terraform apply
```

![Four added, one changed, none destroyed](../images/observability-apply-complete.png)

```bash
gcloud monitoring uptime list-configs
```

![The check, its content matcher, and its TLS validation](../images/observability-uptime-check.png)

Result: the check is `STATIC_IP_CHECKERS` against `https://sindrg.com/healthz`, accepting `STATUS_CLASS_2XX`, matching `ok` in the body, validating the certificate.

![The policy enabled in the console](../images/observability-alert-policy.png)

### Why the threshold is more than one location, not one

The metric carries one series per checker location, so counting the locations currently reporting a failure and opening above one means at least two must fail together.

One location failing is a network path somewhere on the internet, and paging on it is how an alert teaches its reader to dismiss it. Requiring two costs nothing in detection here: one zonal cluster behind one global load balancer has no partial-failure mode, so a real outage fails every location inside the same check period. The rule only filters the case it exists for.

Two fields decide whether the alert is *actionable* rather than merely correct. `auto_close` is set to 30 minutes, because the default is seven days and an incident that recovered on its own would still be open when the next real one arrives. And the documentation body names the first commands to run, working outwards from the Pods to the edge, so the notification does not hand the diagnosis to whoever is holding the phone.

## Slice 3: One dashboard, as code

Status: Complete

### Implemented

- A `google_monitoring_dashboard` built from a template file, so the layout is reviewable and the console is not the source of truth.
- Panels ordered the way they are read during an incident: is the site up, is traffic arriving and in what response class, is latency degrading, did the load balancer or the Pods produce the failure, are containers restarting, and what do the warnings say.

![The dashboard taking data](../images/observability-dashboard.png)

Result: uptime sits at 100%, the edge and backend panels agree on the same traffic, and p50 and p95 track each other closely at a few hundred milliseconds. The `300` class visible alongside `200` is the HTTP to HTTPS redirect from Phase 7 being counted at the edge, which is the redirect working rather than an error.

The traffic on those panels is almost entirely the uptime check. That is the point made at the top of this worklog, drawn: without the check, these panels would be empty and an outage would look identical to a quiet night.

### What is left out, deliberately

There is no ready-replicas-against-desired panel. That metric comes from kube-state-metrics, which is an exporter workload with its own Pod Security and NetworkPolicy consequences in a namespace that enforces `restricted` and denies traffic by default. Restart count and backend responses answer the questions this phase asks, so the exporter is deferred rather than dropped in.

### The console is a scratchpad

The dashboard has autosave enabled in the console, which means edits made there persist and will be silently overwritten by the next `terraform apply`. To keep a console change, export it with `gcloud monitoring dashboards describe <id> --format=json` and commit the result.

## Slice 4: Break it on purpose

Status: Not started

Two drills. The first proves the alert, the second closes the rollout row of the claim table.

- Scale the workload to zero, record the time to the incident opening, restore it, and record the recovery. Scale-to-zero rather than removing the Gateway or the DNS record: those also produce an outage, but recovery then waits on certificate issuance and DNS propagation, which tests Google's provisioning rather than this platform.
- Ship a deliberately broken `/healthz` through the pipeline, let the rollout fail on readiness, and restore the previous version. The result worth recording is that the alert should stay silent, because `maxUnavailable: 0` keeps the previous digest serving throughout a failed deployment.

## Slice 5: The numbers

Status: Not started

- Median deploy duration and the per-step split, plus commit to serving.
- Time from a configuration change to a Ready workload.
- A billing snapshot grouped by SKU, with the main cost sources named rather than only the total.

## Slice 6: Close Milestone 1

Status: Not started

Fill every row of the claim table with a link to its evidence, mark the phase complete, and update the README status and capability table.

## Next

- Run the first drill and record the time from scaling to zero to the incident opening.

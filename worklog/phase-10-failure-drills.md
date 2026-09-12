# Worklog: Phase 10 Failure Drills

Date: 2026-09-12  
Status: complete.

## Goal

Phase 8 built the alert path. It had never been fired.

The evidence rule in [decisions.md](../decisions.md) asks for the success path, the failure path and the recovery. Two drills close that gap:

| Drill | Question | Expected |
| --- | --- | --- |
| Availability | does the alert fire when the site stops serving? | an incident opens, then closes |
| Rollout | does a bad version reach users? | the site never wavers, and the pipeline stops |

The two produce opposite graphs from the same dashboard panel. That contrast is the point.

## Drill A: availability

Scale to zero rather than removing the Gateway or the DNS record. Recovery from those waits on certificate issuance and DNS propagation, which tests Google's provisioning rather than this platform.

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

### Finding: the alert fired after the site was already back

The edge recovered at 10:07:10. The notification start time is 10:07.

Detection took about 3m15s against an outage of 3m19s. The alert was correct and it arrived too late to act on.

The floor is structural rather than a tuning mistake:

- The uptime check runs every 60 seconds per location.
- The condition needs more than one location failing.
- `duration` holds the condition for a further 60 seconds.

Nothing shorter than roughly 3 minutes can open an incident, whatever the alignment period is set to.

This is the intended trade. A blip under 3 minutes is not worth paging, and requiring two locations is what stops one bad network path from waking anyone. The number is recorded here rather than discovered during a real incident.

## Drill B: failed rollout

Break `/healthz` and ship it through the real pipeline. Both probes target that path, so a failing status is enough to stop a rollout.

![return 503 unavailable on line 15](../images/drill-rollout-break.png)

Merged to `main` as a normal change, because `main` requires a pull request and the point is to use the real path.

![PR 53 merged into main](../images/drill-rollout-pr-merged.png)

The edge probe ran throughout. It never left 200.

![Unbroken 200 from 10:56:49 to 11:02:03](../images/drill-rollout-probe-flat.png)

`maxUnavailable: 0` with `maxSurge: 1` creates exactly one surge Pod. It never went Ready.

![Two Pods 1/1, the new one 0/1 at 24s](../images/drill-rollout-surge-pod.png)

Both probes point at `/healthz`, so both fail. Readiness keeps the Pod out of the Service. Liveness restarts the container on its own cycle.

![Liveness and readiness both on /healthz, Ready False, ContainersReady False](../images/drill-rollout-describe.png)

![Restart 1 at 41s, then 2, 3, 4, then CrashLoopBackOff at 2m41s](../images/drill-rollout-watch.png)

![Four restarts at 2m35s, still 0/1](../images/drill-rollout-restarts.png)

The pipeline stopped where it was designed to.

![Wait for the rollout fails at 3m1s, smoke test skipped](../images/drill-rollout-workflow-failed.png)

```
Waiting for deployment "nginx" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
```

The edge, still serving the previous digest.

![HTTP/2 200 and a body of ok at 11:01:14](../images/drill-rollout-edge-200.png)

Restore.

```bash
kubectl rollout undo deployment/nginx -n demo
```

![Rolled back, with a warning about the last-applied-configuration annotation](../images/drill-rollout-undo.png)

![The surge Pod terminated after 7 restarts](../images/drill-rollout-pod-terminated.png)

![Successfully rolled out](../images/drill-rollout-restored.png)

![Revisions 24, 25, 27 and 28, every CHANGE-CAUSE none](../images/drill-rollout-history.png)

### Timeline

| Time (UTC) | Event | Source |
| --- | --- | --- |
| 10:56:49 | Probe starts, 200 | probe loop |
| 10:59:05 | Deploy run 34689846817 starts | `gh run list` |
| 10:59:55 | Surge Pod starts | `kubectl describe` |
| 11:02:03 | Probe still 200 | probe loop |
| 11:03:00 | Rollout wait times out, job fails | workflow run, 3m55s total |
| 11:08 | `rollout undo`, surge Pod terminated | Pod age 8m6s at termination |

| Step | Duration | Result |
| --- | --- | --- |
| Build and push | 10s | pass |
| Apply the Deployment with the new digest | 5s | pass |
| Wait for the rollout | 3m1s | fail, exit 1 |
| Smoke test from inside the cluster | 0s | skipped |

### Finding: the gate held, and the site never knew

Users saw nothing. The probe stayed at 200 for the entire window, and the two healthy Pods were never touched.

`maxUnavailable: 0` is what makes this work. The Deployment is not allowed to remove a healthy Pod until a replacement is Ready, and the replacement never was.

### Finding: CI passed the broken change

Both required checks went green on the pull request that broke the site's health endpoint.

CI validates Terraform and Kubernetes schemas. Nothing in it parses nginx configuration, so a syntactically valid `return 503` is invisible to it.

The rollout gate caught it instead, which is the right layer for a runtime fault. Worth stating plainly: this class of bug is caught after the image is built and pushed, not before.

### Finding: an EndpointSlice lists the address before it is ready

![Three addresses listed, including the Pod that is not Ready](../images/drill-rollout-endpoints.png)

The `ENDPOINTS` column shows `10.20.2.14` alongside the two healthy addresses. That column does not filter on readiness. Each endpoint carries its own `conditions.ready`, and that condition is what gates traffic.

Reading the column alone during an incident would suggest three backends were serving. The flat probe and `Ready: False` on the Pod are what say otherwise.

To see the condition rather than the column:

```bash
kubectl get endpointslices -n demo -l kubernetes.io/service-name=nginx -o yaml | grep -A3 addresses
```

### Smaller notes

- `rollout undo` warns that the `last-applied-configuration` annotation is not updated. The pipeline applies the full manifest on every deploy, so the next successful run reconciles it.
- `rollout history` records every revision with `CHANGE-CAUSE: <none>`. The history says a rollback happened and not why. The workflow run is the only record of the cause.

## What the two drills prove together

| Claim | Drill | Evidence |
| --- | --- | --- |
| Monitoring works | A | the alert opened at 10:07, about 3m15s after the outage started |
| Rollout is controlled | B | the pipeline failed at the rollout gate and the previous digest kept serving |

Drill A produced a notch in the uptime panel. Drill B produced a flat line across a window where the pipeline went red.

One detection limit is now written down: outages shorter than roughly 3 minutes do not open an incident.

## Next

Phase 8 Slice 5, the deploy timings and the cost snapshot, then Slice 6 to close Milestone 1.

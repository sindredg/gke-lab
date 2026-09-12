# Worklog: Phase 10 Failure Drills

Date: 2026-09-12  
Status: Complete.

## Goal

Fire the signal path [Phase 8](phase-08-observability.md) built, and prove a bad version cannot reach users.

| Drill | Question | Expected |
| --- | --- | --- |
| Availability | does the alert fire when the site stops serving? | an incident opens, then closes |
| Rollout | does a bad version reach users? | the pipeline stops, the site does not move |

## Drill A: availability

Scale to zero rather than pulling the Gateway or the DNS record. Recovery from those waits on certificate issuance and DNS propagation, which tests Google's provisioning rather than this platform.

Baseline.

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

503 rather than 502: the backend service has no healthy backend to forward to.

![HTTP/2 503 from the edge](../images/drill-availability-edge-503.png)

```bash
date -u; kubectl scale deployment/nginx -n demo --replicas=2
kubectl rollout status deployment/nginx -n demo
```

![Scaled to two at 10:06:54 UTC, rollout successful](../images/drill-availability-restore.png)

The edge recovered 16 seconds after the restore.

![503 through 10:06:58, then 200 from 10:07:10](../images/drill-availability-probe-recovery.png)

![Both endpoints back on port 8080, one per node](../images/drill-availability-endpoints-restored.png)

![HTTP/2 200 and a body of ok](../images/drill-availability-edge-200.png)

![The uptime panel dipping to 45.24%](../images/drill-availability-uptime-dip.png)

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

### Finding: detection has a three minute floor

The edge recovered at 10:07:10. The alert start time is 10:07. Detection took about 3m15s against an outage of 3m19s.

The floor is structural:

- the check runs every 60 seconds per location
- the condition needs more than one location failing
- `duration` holds the condition a further 60 seconds

Nothing shorter than roughly three minutes can open an incident. That is the intended trade, now measured rather than assumed.

## Drill B: failed rollout

Break `/healthz` and ship it through the real pipeline. Both probes target that path.

![return 503 unavailable on line 15](../images/drill-rollout-break.png)

![PR 53 merged into main](../images/drill-rollout-pr-merged.png)

The edge probe never left 200.

![Unbroken 200 from 10:56:49 to 11:02:03](../images/drill-rollout-probe-flat.png)

`maxUnavailable: 0` with `maxSurge: 1` creates exactly one surge Pod. It never went Ready.

![Two Pods 1/1, the new one 0/1 at 24s](../images/drill-rollout-surge-pod.png)

Readiness keeps the Pod out of the Service. Liveness restarts the container on its own cycle.

![Liveness and readiness both on /healthz, Ready False](../images/drill-rollout-describe.png)

![Restart 1 at 41s, then 2, 3, 4, then CrashLoopBackOff at 2m41s](../images/drill-rollout-watch.png)

![Four restarts at 2m35s, still 0/1](../images/drill-rollout-restarts.png)

![Wait for the rollout fails at 3m1s, smoke test skipped](../images/drill-rollout-workflow-failed.png)

```
Waiting for deployment "nginx" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
```

![HTTP/2 200 and a body of ok at 11:01:14](../images/drill-rollout-edge-200.png)

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

### Finding: the gate held

Users saw nothing. `maxUnavailable: 0` will not retire a healthy Pod for one that is not Ready.

### Finding: CI passed the broken change

Both required checks went green on the pull request that broke the health endpoint. CI validates Terraform and Kubernetes schemas, and nothing parses nginx configuration. This class of fault is caught after the image is built, not before.

### Finding: an EndpointSlice lists an address before it is ready

![Three addresses listed, including the Pod that is not Ready](../images/drill-rollout-endpoints.png)

The `ENDPOINTS` column showed three backends while two were serving. It does not filter on readiness. Each endpoint carries its own `conditions.ready`, and that is what gates traffic.

```bash
kubectl get endpointslices -n demo -l kubernetes.io/service-name=nginx -o yaml | grep -A3 addresses
```

### Notes

- `rollout undo` leaves the `last-applied-configuration` annotation stale. The next pipeline apply reconciles it.
- `rollout history` records every revision as `CHANGE-CAUSE: <none>`. The workflow run is the only record of why.

## Result

| Claim | Evidence |
| --- | --- |
| Monitoring works | the alert opened about 3m15s after the outage began, and closed on recovery |
| Rollout is controlled | the pipeline failed at the gate, and the previous digest kept serving |

Drill A cut a notch in the uptime panel. Drill B left it flat while the pipeline went red.

Postmortem: [the availability drill](postmortem-availability-drill.md).

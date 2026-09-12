# Postmortem: sindrg.com unavailable, 2026-09-12

Severity: none, deliberate.  
Duration: 3m19s at the edge.  
Impact: `/` returned 503. `/sky`, `/api` and `/static` were unaffected.

## Summary

`nginx` was scaled to zero to test whether the alert built in [Phase 8](phase-08-observability.md) fires. It did. It also arrived as the site was already recovering.

## Timeline

| Time (UTC) | Event |
| --- | --- |
| 10:03:45 | `nginx` scaled to zero |
| 10:03:51 | Edge returns 503, 6 seconds later |
| 10:06:54 | `nginx` scaled back to two |
| 10:07:10 | Edge returns 200 |
| 10:07 | Alert opens |

Detection: about 3m15s. Recovery: 16s from the restore.

## What worked

The Service emptied and the edge reflected it within 6 seconds, so the blast radius was accurate and immediate. `sky` was untouched, which confirms the two workloads fail independently.

The content matcher earned its place. The check requires `ok` in the body, so a 200 from anything that is not this workload would still have failed.

## What did not

The notification is not actionable for an outage of this length. It opened at 10:07 and the site recovered at 10:07:10. An operator reading it would have found a healthy site and no cause.

## Would the runbook have helped?

The alert carries five commands, Pods outwards to the edge. Walked against what was actually true:

| Step | Would it have found the cause? |
| --- | --- |
| 1. `kubectl get pods` | Yes. Zero `nginx` Pods, immediately. |
| 2. `kubectl get endpointslices` | Yes, confirms the empty Service. |
| 3. `kubectl describe gateway` | No, the Gateway was healthy. |
| 4. Backend health in the console | No. |
| 5. `curl /healthz` | No, it answers what, not why. |

Step 1 was correct and sufficient. The ordering holds.

The runbook does not say what to do when the Pods are simply gone. It assumes a rollout that failed readiness, which is the [Phase 10](phase-10-failure-drills.md) drill B case. A deleted or scaled-away workload has no rollout to inspect.

## Actions

| Action | Status |
| --- | --- |
| Record the three minute detection floor | Done, [Phase 10](phase-10-failure-drills.md) |
| Add "if Pods are absent rather than unready, check recent scale and apply operations" to the alert documentation | Open |
| Reduce detection below three minutes | Rejected |

Detection is not worth shortening. It would mean paging on one checker location, which teaches the reader to dismiss the alert. The floor is a deliberate cost of requiring two.

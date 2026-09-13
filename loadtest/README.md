# Load test harness

The scripts behind [Phase 12](../plan.md#phase-12-load-and-autoscaling). Every run uses these files unchanged, so a difference between two runs belongs to the platform.

| File | Runs on | Does |
| --- | --- | --- |
| `loadgen.sh` | operator | creates and deletes the load generator VM, its VPC, and an IAP-only SSH rule |
| `ramp.js` | load generator | steps sky through fixed arrival rates until p95 exceeds 500ms or errors exceed 1% |
| `rollout.js` | load generator | holds a constant rate during a rollout and logs every failed request |
| `record.sh` | operator | snapshots the HPA, Deployments, Pods, nodes and quota every 5s, and streams events |

Results land in `results/`, which git ignores. The worklog carries what they show.

## Session

Create the generator and copy the scripts to it. `up` waits for k6 to install and prints its version.

```bash
loadtest/loadgen.sh up
loadtest/loadgen.sh copy
```

Calibrate once per session. The generator is not the bottleneck if `dropped_iterations` is 0 and `vmstat` shows idle CPU above 30% at the step that fails.

```bash
loadtest/loadgen.sh ssh
cd ~/loadtest && k6 run -e RUN=calibrate -e STEP_SECONDS=20 ramp.js
```

```bash
loadtest/loadgen.sh ssh --command='vmstat 5'
```

Start the recorder on the operator's machine, then the run on the generator.

```bash
loadtest/record.sh a-ramp
```

```bash
cd ~/loadtest && k6 run -e RUN=a-ramp ramp.js
```

For a rollout run, let `rollout.js` hold its rate for a minute, then restart each workload in turn.

```bash
cd ~/loadtest && k6 run -e RUN=a-rollout -e DURATION=8m --log-output=file=results/a-rollout-failures.log rollout.js
```

```bash
date -u; kubectl rollout restart deployment/sky -n demo && kubectl rollout status deployment/sky -n demo
date -u; kubectl rollout restart deployment/nginx -n demo && kubectl rollout status deployment/nginx -n demo
```

Bring the results home and delete the generator. `down` ends by listing the project's networks, which should be `gke-vpc` alone.

```bash
loadtest/loadgen.sh pull
loadtest/loadgen.sh down
```

## Runs

| Step | Runs | `RUN` names |
| --- | --- | --- |
| A | ramp, rollout | `a-ramp`, `a-rollout` |
| B | rollout | `b-rollout` |
| C | ramp | `c-ramp` |
| D | ramp | `d-ramp` |

`RATE` for the rollout runs is the same in A and B, at about half the saturation rate from `a-ramp`.

## Reading a run

| Question | Where |
| --- | --- |
| saturation rate | the last `stepNN` whose thresholds pass in the k6 summary |
| p95 per step | `http_req_duration{scenario:stepNN_...}` in `results/*-k6.json` |
| rollout error window | first and last line of `*-failures.log` |
| quota stall | `DECLARED` above `AVAILABLE` in `*-cluster.log`, `FailedCreate` in `*-events.log` |
| new node | `TriggeredScaleUp` in `*-events.log`, a third node in `*-cluster.log` |
| throttling | the sky CPU throttling panel on the dashboard |

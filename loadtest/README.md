# Load test harness

The scripts behind [Phase 12](../plan.md#phase-12-load-and-autoscaling). Every run uses these files unchanged, so a difference between two runs belongs to the platform.

| File | Runs on | Does |
| --- | --- | --- |
| `loadgen.sh` | operator | creates and deletes the load generator VM, its VPC, and an IAP-only SSH rule |
| `ramp.js` | load generator | steps sky through fixed arrival rates until a settled step's p95 exceeds 500ms or its errors exceed 1% |
| `rollout.js` | load generator | holds a constant rate during a rollout and logs every failed request |
| `record.sh` | operator | snapshots the HPA, Deployments, Pods, nodes and quota every 5s, and streams events |

Results land in `results/`, which git ignores. The worklog carries what they show.

## How a ramp step is judged

Each request is tagged `settling` for the first `SETTLE_SECONDS` of its step and `settled` after. Only settled requests decide the step, and the decision waits for 10s of them.

| Run | `STEP_SECONDS` | `SETTLE_SECONDS` | Why |
| --- | --- | --- | --- |
| fixed replicas | 60 | 15 | skips the first seconds of a step, which can be slow for reasons that pass |
| autoscaling | 180 | 90 | gives the HPA time to add Pods before the step counts |

Every request is still reported per step, settling ones included, as `http_req_duration{scenario:stepNN_...}`.

## Session

Create the generator and copy the scripts to it. `up` waits for k6 to install and prints its version.

```bash
loadtest/loadgen.sh up
loadtest/loadgen.sh copy
```

Run k6 inside tmux on the generator. An IAP tunnel can drop mid-run, and `tmux attach -t k6` picks the run back up.

```bash
loadtest/loadgen.sh ssh
tmux new -A -s k6
```

Calibrate once per session. The generator is not the bottleneck if `dropped_iterations` is 0 and `vmstat` shows idle CPU above 30% at the step that fails.

```bash
cd ~/loadtest && k6 run -e RUN=calibrate -e STEP_SECONDS=20 -e SETTLE_SECONDS=5 ramp.js
```

```bash
loadtest/loadgen.sh ssh --command='vmstat 5'
```

Start the recorder on the operator's machine, then the run on the generator.

```bash
loadtest/record.sh c0-ramp
```

```bash
cd ~/loadtest && k6 run -e RUN=c0-ramp -e STEP_SECONDS=180 -e SETTLE_SECONDS=90 ramp.js
```

For a rollout run, let `rollout.js` hold its rate for a minute, then restart each workload in turn.

```bash
cd ~/loadtest && k6 run -e RUN=b-rollout -e RATE=20 -e DURATION=8m --log-output=file=results/b-rollout-failures.log rollout.js
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

| Step | Runs | `RUN` names | Steps |
| --- | --- | --- | --- |
| A | ramp, rollout | `a-ramp`, `a-rollout` | 60s, judged from the step's first request |
| B | rollout | `b-rollout`, `b-rollout-2` | |
| B2 | ramp | `b2-ramp` | 60s, judged from the step's first request |
| C0 | ramp | `c0-ramp` | 180s, settle 90s |
| C | ramp | `c-ramp` | 180s, settle 90s |
| D | ramp | `d-ramp` | 180s, settle 90s |

`RATE` for the rollout runs is 20, about half the saturation rate from `a-ramp`. C0 is the fixed-replica reference that C and D compare against, on the same step and settle times.

## Reading a run

| Question | Where |
| --- | --- |
| saturation rate | the last `stepNN` whose `window:settled` thresholds pass in the k6 summary |
| p95 per step | `http_req_duration{scenario:stepNN_...}` for every request, `...,window:settled}` for the settled part |
| rollout error window | first and last line of `*-failures.log` |
| quota stall | `DECLARED` above `AVAILABLE` in `*-cluster.log`, `FailedCreate` in `*-events.log` |
| new node | `TriggeredScaleUp` in `*-events.log`, a third node in `*-cluster.log` |
| throttling | the sky CPU throttling panel on the dashboard |

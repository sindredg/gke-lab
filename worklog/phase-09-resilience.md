# Worklog: Phase 9 Surviving a Node

Date: 2026-09-08  
Status: Complete.

## Goal

Make the second replica survive a node going away, not just a rollout.

## Problem

Redundancy needs three things true at once. Each one failed here while the others held:

| Requirement | Set by | Observed failure |
| --- | --- | --- |
| A second copy exists | `replicas: 2` | two Pods on one node |
| Somewhere else to put it | node floor of two | floor raised, no node added |
| Something moves it there | the scheduler | every Pod on the newest node |

- `maxUnavailable: 0` protects a rollout, not an eviction.
- `auto_upgrade` and `auto_repair` evict Pods without asking.
- A `PodDisruptionBudget` covers evictions, but on a single node it blocks the drain instead of pacing it.
- So the node floor and the budgets ship as one change.

## Slice 1: Raise the node floor to two

Status: Complete

### Changes

- `min_node_count`: 1 to 2, in the root module.
- `initial_node_count`: decoupled from it, in `modules/gke/node_pool.tf`.
- `maintenance_policy`: daily window at 01:00 UTC, so node replacement lands at night in Helsinki.

### Warning: `initial_node_count` is ForceNew

It was wired to `var.min_node_count`. It sets only the size the pool is born at, and changing it destroys and recreates the pool. Pin it to `1` and let the floor move on its own.

```
# module.gke.google_container_cluster.main     will be updated in-place
# module.gke.google_container_node_pool.general will be updated in-place
      ~ total_min_node_count = 1 -> 2

Plan: 0 to add, 4 to change, 0 to destroy.
```

The other two changed resources are pre-existing observability drift, present on a clean checkout of `main`.

### The floor alone added no node

```bash
kubectl get nodes
```

![One node, 22 hours old, well after the apply](../images/resilience-single-node.png)

| Reading | Value |
| --- | --- |
| `totalMinNodeCount` in GCP | 2 |
| Managed instance group target | 1 |
| Nodes 15 minutes later | 1 |
| Regional E2 quota | 24 vCPU, against one 2-vCPU node |

Result: quota was not the constraint. The autoscaler treats a minimum as a bound it respects, not an instruction it acts on. A manual resize was required.

![The pool resized to two nodes in each zone it spans](../images/resilience-resize.png)

```bash
kubectl get nodes
```

![The second node Ready, 45 seconds old](../images/resilience-two-nodes.png)

Check the instance group, not the Terraform output.

## Slice 2: Spread the Pods across both nodes

Status: Complete

### A new node does not rebalance existing Pods

```bash
kubectl get pods -n demo -o wide
```

![All four Pods on the older node, 5gn3](../images/resilience-pods-together.png)

A rolling restart moved all four Pods to the *new* node instead of splitting them:

- `topologySpreadConstraints` count every Pod matching the selector, including old replicas still running.
- Each new Pod saw two on the old node and none on the new one, and chose the new one. Twice.
- Then the old Pods terminated. `ScheduleAnyway` is a preference, so nothing overrode it.

Restarting again reproduces the same result.

### Fix: delete one Pod per Deployment

A single replacement carries no old-revision skew, so the emptier node wins.

```bash
kubectl get pods -n demo -o wide
```

![One nginx and one sky on each node, 5gn3 and n75s](../images/resilience-pods-spread.png)

- `ScheduleAnyway` stays, now for a second reason: with `maxSkew: 1` across exactly two nodes, `DoNotSchedule` would refuse to reschedule during a drain, because the surviving node would sit at skew 2.
- Durable fix: `matchLabelKeys: ["pod-template-hash"]` confines the calculation to one ReplicaSet. Applied in [Phase 11](phase-11-hardening.md). Until then, every rollout needed this rebalance by hand.

## Slice 3: Add disruption budgets

Status: Complete

### Changes

- `PodDisruptionBudget` with `minAvailable: 1` on both workloads.
- Applied by an operator, not the pipeline: the delivery Role holds `patch` and not `create`, and covers Deployments rather than policy objects.

```bash
kubectl get pdb -n demo
```

![Both budgets allowing one disruption](../images/resilience-budgets.png)

| `ALLOWED DISRUPTIONS` | Effect on a drain |
| --- | --- |
| 1 | paced |
| 0 | blocked |

On a single-node pool the value would have been `0` from the moment the budget was applied.

## Cost

| Item | Change |
| --- | --- |
| Second `e2-standard-2`, running continuously | node line roughly doubles |
| Maintenance window | free |
| Disruption budgets | free |

Spot nodes would more than offset this, and preemptions would exercise the self-healing Phase 2 documents. Deferred because `spot` is `ForceNew` on the node pool: migrate as a second pool to drain onto, not as a swap.

## Open

- Spot migration.

Closed in [Phase 11](phase-11-hardening.md): `matchLabelKeys` on both spread constraints, and the dashboard drift that kept `terraform plan` from ever being clean.

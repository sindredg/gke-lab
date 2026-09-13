#!/usr/bin/env bash
# Records what the cluster does during a load test, so the client's view in k6 can be lined up against the platform's by timestamp.
# Runs from the operator's machine, not the load generator, and stops on Ctrl+C.
#
# Usage: loadtest/record.sh [run-name]
set -euo pipefail

NAMESPACE="${NAMESPACE:-demo}"
INTERVAL="${INTERVAL:-5}"
RUN="${1:-run}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DIR="$(dirname "$0")/results"
SNAPSHOTS="$DIR/$RUN-$STAMP-cluster.log"
EVENTS="$DIR/$RUN-$STAMP-events.log"

mkdir -p "$DIR"

# Events expire after an hour and a later `kubectl get events` loses the order, so they are streamed as they happen.
# FailedCreate carries a quota rejection and TriggeredScaleUp carries the cluster autoscaler's decision.
kubectl get events -n "$NAMESPACE" --watch-only \
  -o custom-columns='TIME:.lastTimestamp,TYPE:.type,REASON:.reason,OBJECT:.involvedObject.name,MESSAGE:.message' \
  >> "$EVENTS" &
EVENTS_PID=$!
trap 'kill "$EVENTS_PID" 2>/dev/null || true; echo; echo "Wrote $SNAPSHOTS and $EVENTS"' EXIT

echo "Recording every ${INTERVAL}s to $SNAPSHOTS. Ctrl+C to stop."

while true; do
  {
    echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Absent until the HPA exists, which is itself worth seeing in the baseline.
    kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null || true

    # Declared against available is the quota stall: the HPA raises the first and the second stops following.
    kubectl get deployments -n "$NAMESPACE" --no-headers \
      -o custom-columns='NAME:.metadata.name,DECLARED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas,UPDATED:.status.updatedReplicas'

    kubectl get pods -n "$NAMESPACE" --no-headers \
      -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,NODE:.spec.nodeName'

    kubectl get nodes --no-headers

    kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null || true

    kubectl describe resourcequota -n "$NAMESPACE" | grep -E 'limits.cpu|requests.cpu|pods' || true
  } >> "$SNAPSHOTS" 2>&1

  sleep "$INTERVAL"
done

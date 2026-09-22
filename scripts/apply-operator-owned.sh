#!/usr/bin/env bash
# Applies what an operator owns in one kubernetes/ directory, and skips the Deployments a pipeline owns.
#
# The committed nginx and sky Deployments name the digest they were bootstrapped with. The pipeline
# renders the current digest at deploy time and does not commit it back, so applying either file by
# hand rolls the workload back to an old image. Extra arguments go to kubectl:
#   ./scripts/apply-operator-owned.sh sky --dry-run=server
set -euo pipefail

cd "$(dirname "$0")/.."

dir=${1:-}
if [ -z "$dir" ] || [ ! -d "kubernetes/$dir" ]; then
  echo "usage: $0 <platform|nginx|sky|agents> [kubectl apply arguments]" >&2
  exit 2
fi
shift

pipeline_owned=(kubernetes/nginx/deployment.yml kubernetes/sky/deployment.yml)

args=()
for f in "kubernetes/$dir"/*.yml; do
  owned=false
  for p in "${pipeline_owned[@]}"; do
    [ "$f" = "$p" ] && owned=true
  done
  if "$owned"; then
    echo "skipped $f: the deploy pipeline applies it" >&2
  else
    args+=(-f "$f")
  fi
done

kubectl apply "${args[@]}" "$@"

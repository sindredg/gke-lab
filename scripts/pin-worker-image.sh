#!/usr/bin/env bash
# Moves the triage worker to a published digest, changing the image and IMAGE_DIGEST together.
#
# The Deploy triage worker run prints the digest. Commit the result, and an operator applies it:
#   ./scripts/pin-worker-image.sh sha256:<digest>
#   kubectl apply -f kubernetes/agents/deployment.yml
set -euo pipefail

cd "$(dirname "$0")/.."

digest=${1:-}
if ! printf '%s' "$digest" | grep -qE '^sha256:[0-9a-f]{64}$'; then
  echo "usage: $0 sha256:<64 hex characters>" >&2
  exit 2
fi

manifest=kubernetes/agents/deployment.yml
sed -i -E "s#(image: [^@]+/triage-worker@)sha256:[0-9a-f]{64}#\1${digest}#" "$manifest"
sed -i -E "/name: IMAGE_DIGEST/{n;s#value: sha256:[0-9a-f]{64}#value: ${digest}#}" "$manifest"

./scripts/check-image-digests.sh
grep -c "$digest" "$manifest" | xargs printf '%s: the digest appears %s times\n' "$manifest"

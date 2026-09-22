#!/usr/bin/env bash
# Checks that every Deployment declaring IMAGE_DIGEST names the digest its image line pins.
#
# The triage worker records IMAGE_DIGEST with every verdict. A rollout that moves the image and not
# the variable writes the wrong provenance, and nothing else fails.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
checked=0
for f in kubernetes/*/deployment.yml; do
  grep -q 'name: IMAGE_DIGEST' "$f" || continue
  checked=$((checked + 1))
  pinned=$(grep -oP '^\s*image: \S+@\Ksha256:[0-9a-f]{64}' "$f" | head -1 || true)
  declared=$(grep -A1 'name: IMAGE_DIGEST' "$f" | grep -oP 'value: \Ksha256:[0-9a-f]{64}' || true)
  if [ -z "$pinned" ] || [ "$pinned" != "$declared" ]; then
    printf '%s: the image pins %s and IMAGE_DIGEST says %s\n' "$f" "${pinned:-no digest}" "${declared:-nothing}"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  printf 'ok: %d Deployments declare the digest they pin\n' "$checked"
fi
exit "$status"

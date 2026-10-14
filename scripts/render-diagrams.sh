#!/usr/bin/env bash
# Renders each scripts/diagrams/*.html to light and dark PNGs in images/diagrams/.
set -euo pipefail

cd "$(dirname "$0")/.."

chrome=${CHROME:-$(command -v chromium || command -v google-chrome || true)}
if [ -z "$chrome" ]; then
  printf 'set CHROME to a Chromium binary\n' >&2
  exit 1
fi

mkdir -p images/diagrams
for src in scripts/diagrams/*.html; do
  name=$(basename "$src" .html)
  # The canvas size is the SVG's own width and height attributes.
  read -r width height < <(grep -m1 -oE '<svg [^>]*width="[0-9]+" height="[0-9]+"' "$src" |
    sed -E 's/.*width="([0-9]+)" height="([0-9]+)"/\1 \2/')
  for theme in light dark; do
    flags=()
    [ "$theme" = dark ] && flags+=(--force-dark-mode)
    "$chrome" --headless --no-sandbox --disable-gpu --hide-scrollbars \
      --force-device-scale-factor=2 --window-size="$width,$height" \
      --virtual-time-budget=8000 "${flags[@]}" \
      --screenshot="$PWD/images/diagrams/$name-$theme.png" \
      "file://$PWD/$src" 2>/dev/null
  done
done

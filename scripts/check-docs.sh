#!/usr/bin/env bash
# Checks that every documentation link, anchor and screenshot resolves.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
report() {
  printf '%s\n' "$1"
  status=1
}

# GitHub builds a heading anchor by lowercasing, dropping punctuation, and
# replacing spaces with hyphens.
slugs() {
  grep -E '^#{1,6} ' "$1" |
    sed -E 's/^#+ //; s/`//g' |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9 _-]//g; s/ /-/g'
}

links=0
while IFS= read -r doc; do
  dir=$(dirname "$doc")
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    links=$((links + 1))
    path=${link%%#*}
    anchor=""
    case "$link" in
      *'#'*) anchor=${link#*#} ;;
    esac

    if [ -z "$path" ]; then
      target=$doc
    else
      target=$(realpath -m --relative-to=. "$dir/$path")
    fi

    if [ ! -f "$target" ]; then
      report "broken link    $doc -> $link"
      continue
    fi
    if [ -n "$anchor" ] && ! slugs "$target" | grep -qx -- "$anchor"; then
      report "broken anchor  $doc -> $link"
    fi
  done < <(grep -oE '\]\([^)]+\)' "$doc" | sed -E 's/^\]\(//; s/\)$//' | grep -v '^http' || true)
done < <(git ls-files '*.md')

# A screenshot nobody references is dead weight, and a reference to a
# screenshot that was never committed renders as a broken image on GitHub.
referenced=$(git ls-files '*.md' | xargs grep -hoE '\((\.\./)?images/[^)]+\)' |
  tr -d '()' | sed 's|^\.\./||' | sort -u)
tracked=$(git ls-files 'images/*' | sort)

while IFS= read -r image; do
  [ -n "$image" ] || continue
  report "image not committed  $image"
done < <(comm -13 <(printf '%s\n' "$tracked") <(printf '%s\n' "$referenced"))

while IFS= read -r image; do
  [ -n "$image" ] || continue
  report "image unreferenced   $image"
done < <(comm -23 <(printf '%s\n' "$tracked") <(printf '%s\n' "$referenced"))

if [ "$status" -eq 0 ]; then
  printf 'ok: %s links and %s images resolve\n' "$links" "$(printf '%s\n' "$tracked" | wc -l)"
fi
exit "$status"

#!/bin/sh
# Compare hand-written .ml/.mli files in examples/mirage against mirage-skeleton.
# Usage: ./scripts/diff-mirage-skeleton.sh [--quiet]
#
# Skips generated files (main.ml, main.mli, certs_data.*, keys_data.*)
# and adapter files (which have no mirage-skeleton equivalent).

set -e

SKELETON="${MIRAGE_SKELETON:-$HOME/git/mirage-skeleton}"
EXAMPLES="$(cd "$(dirname "$0")/.." && pwd)/examples/mirage"
quiet=false

if [ "$1" = "--quiet" ]; then
  quiet=true
fi

if [ ! -d "$SKELETON" ]; then
  echo "error: mirage-skeleton not found at $SKELETON" >&2
  echo "set MIRAGE_SKELETON to the correct path" >&2
  exit 1
fi

diffs=0
checked=0
missing=0

# Map from examples/mirage/<category>/<name>/file.ml
# to   mirage-skeleton/<category>/<name>/file.ml
for f in $(find "$EXAMPLES" \( -name '*.ml' -o -name '*.mli' \) | sort); do
  # Skip generated files
  base=$(basename "$f")
  case "$base" in
    main.ml|main.mli|certs_data.*|keys_data.*) continue ;;
  esac

  # Skip adapters (no mirage-skeleton equivalent)
  case "$f" in
    */adapters/*) continue ;;
  esac

  # Compute relative path from examples/mirage/
  rel="${f#$EXAMPLES/}"

  # The corresponding mirage-skeleton path
  skel="$SKELETON/$rel"

  if [ ! -f "$skel" ]; then
    missing=$((missing + 1))
    if [ "$quiet" = false ]; then
      echo "MISSING  $rel  (not in mirage-skeleton)"
    fi
    continue
  fi

  checked=$((checked + 1))
  if ! diff -q "$skel" "$f" >/dev/null 2>&1; then
    diffs=$((diffs + 1))
    echo "DIFF     $rel"
    if [ "$quiet" = false ]; then
      diff -u "$skel" "$f" || true
      echo
    fi
  fi
done

echo "---"
echo "checked: $checked  diffs: $diffs  missing: $missing"
exit $diffs

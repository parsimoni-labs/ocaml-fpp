#!/bin/bash
# Compare hand-written .ml/.mli files in examples/mirage against mirage-skeleton.
# Also checks that every example directory has a run.t and a dune file.
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
  # Normalise formatting before comparing to ignore ocamlformat differences
  case "$base" in
    *.mli) kind=--intf ;; *) kind=--impl ;;
  esac
  fmt_skel=$(ocamlformat --disable-conf-files --enable-outside-detected-project "$kind" "$skel" 2>/dev/null) || fmt_skel=$(cat "$skel")
  fmt_f=$(ocamlformat --disable-conf-files --enable-outside-detected-project "$kind" "$f" 2>/dev/null) || fmt_f=$(cat "$f")
  if [ "$fmt_skel" != "$fmt_f" ]; then
    diffs=$((diffs + 1))
    echo "DIFF     $rel"
    if [ "$quiet" = false ]; then
      diff -u <(echo "$fmt_skel") <(echo "$fmt_f") || true
      echo
    fi
  fi
done

# Check that every example directory (containing config.fpp) has run.t and dune
no_runt=0
no_dune=0
for cfg in $(find "$EXAMPLES" -name 'config.fpp' | sort); do
  dir=$(dirname "$cfg")
  rel="${dir#$EXAMPLES/}"

  if [ ! -f "$dir/run.t" ]; then
    no_runt=$((no_runt + 1))
    if [ "$quiet" = false ]; then
      echo "NO run.t  $rel"
    fi
  fi

  if [ ! -f "$dir/dune" ]; then
    no_dune=$((no_dune + 1))
    if [ "$quiet" = false ]; then
      echo "NO dune   $rel"
    fi
  fi
done

echo "---"
echo "checked: $checked  diffs: $diffs  missing: $missing"
echo "examples missing run.t: $no_runt  missing dune: $no_dune"
exit $((diffs + no_runt + no_dune))

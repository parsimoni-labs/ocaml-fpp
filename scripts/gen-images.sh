#!/bin/sh
# Regenerate topology PNGs via fprime-visual and FPV JSON.
#
# Usage:
#   ./scripts/gen-images.sh [TOPOLOGY ...]
#
# Without arguments, generates for all topologies.
# With arguments, generates for the named topologies only.
#
# Outputs:
#   images/<Topology>.json  — FPV JSON (fprime-visual format)
#   images/<Topology>.png   — Screenshot from fprime-visual
#
# Requires: ofpp (built via dune), fprime-visual, node, npx playwright

set -eu

MIRAGE="examples/mirage"
FILES=$(find "$MIRAGE" -name '*.fpp' | sort)
OUTDIR="images"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUTDIR"

if [ $# -ge 1 ]; then
  topos="$*"
else
  topos=$(grep -h '^topology ' $FILES | sed 's/topology \([^ ]*\).*/\1/')
fi

# --- Generate JSON files ---
for topo in $topos; do
  echo "  $topo.json"
  dune exec -- ofpp fpv --topology "$topo" -o "$OUTDIR/$topo.json" $FILES
done

# --- Screenshot PNGs via fprime-visual + Playwright ---
ABSDIR="$(cd "$OUTDIR" && pwd)"
FOLDER="$(basename "$ABSDIR")"

# Pick a random port to avoid conflicts.
PORT=$((10000 + RANDOM % 50000))

# Start fprime-visual in the background.
fprime-visual --source-dir "$ABSDIR" --gui-port "$PORT" &
FPV_PID=$!

cleanup() {
  kill "$FPV_PID" 2>/dev/null || true
  wait "$FPV_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for the server to be ready.
echo "Waiting for fprime-visual on port $PORT..."
attempts=0
while ! curl -s -o /dev/null "http://localhost:$PORT/" 2>/dev/null; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 30 ]; then
    echo "ERROR: fprime-visual did not start after 30 seconds" >&2
    exit 1
  fi
  sleep 1
done

# Filter out topologies with no connections (empty graphs can't render).
screenshot_topos=""
for topo in $topos; do
  if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('connections') else 1)" "$OUTDIR/$topo.json" 2>/dev/null; then
    screenshot_topos="$screenshot_topos $topo"
  else
    echo "  $topo: no connections, skipping screenshot"
  fi
done

echo "Taking screenshots..."
if [ -n "$screenshot_topos" ]; then
  node "$SCRIPT_DIR/screenshot-topologies.js" "$PORT" "$FOLDER" "$OUTDIR" $screenshot_topos
fi

echo "Done. Output in $OUTDIR/"

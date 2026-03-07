#!/bin/sh
# Generate FPV JSON from mirage FPP topologies.
#
# Usage:
#   ./scripts/fpv.sh [TOPOLOGY]
#
# Without arguments, generates JSON for all website topologies.
# With an argument, generates JSON for that specific topology.
#
# Requires: ofpp (built via dune build)

set -eu

MIRAGE="examples/mirage"
FILES=$(find "$MIRAGE" -name '*.fpp' | sort)
OUTDIR="examples/mirage/fpv"

mkdir -p "$OUTDIR"

if [ $# -ge 1 ]; then
  topos="$*"
else
  topos=$(grep -h '^topology ' $FILES | sed 's/topology \([^ ]*\).*/\1/')
fi

for topo in $topos; do
  out="$OUTDIR/$topo.json"
  echo "Generating $out ..."
  dune exec -- ofpp fpv --topology "$topo" -o "$out" $FILES
done

echo "Done. FPV JSON files in $OUTDIR/"

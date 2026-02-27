#!/bin/sh
# Regenerate topology diagrams and FPV JSON.
#
# Usage:
#   ./scripts/gen-images.sh [TOPOLOGY ...]
#
# Without arguments, generates for all topologies.
# With arguments, generates for the named topologies only.
#
# Outputs:
#   images/<Topology>.svg   — Graphviz topology diagram
#   images/<Topology>.png   — Graphviz topology diagram (raster)
#   images/<Topology>.json  — FPV JSON (fprime-visual format)
#
# Requires: ofpp (built via dune), dot (graphviz)

set -eu

MIRAGE="examples/mirage"
FILES="$MIRAGE/types.fpp $MIRAGE/devices.fpp $MIRAGE/stacks.fpp $MIRAGE/websites.fpp"
OUTDIR="images"

mkdir -p "$OUTDIR"

if [ $# -ge 1 ]; then
  topos="$*"
else
  topos="
    TcpipStack SocketStack DnsStack
    StaticWebsite StaticWebsiteWithDns TarWebsite FatWebsite
    UnixWebsite UnixWebsiteWithDns UnixTestWebsite
  "
fi

for topo in $topos; do
  echo "  $topo"
  dune exec -- ofpp dot --topology "$topo" -o "$OUTDIR/$topo.svg" $FILES
  dune exec -- ofpp dot --topology "$topo" -o "$OUTDIR/$topo.png" $FILES
  dune exec -- ofpp fpv --topology "$topo" -o "$OUTDIR/$topo.json" $FILES
done

echo "Done. Output in $OUTDIR/"

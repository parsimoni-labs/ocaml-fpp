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
FILES="$MIRAGE/types.fpp $MIRAGE/devices.fpp $MIRAGE/stacks.fpp $MIRAGE/websites.fpp $MIRAGE/skeleton.fpp"
OUTDIR="examples/mirage/fpv"

mkdir -p "$OUTDIR"

if [ $# -ge 1 ]; then
  topos="$*"
else
  topos="TcpipStack SocketStack DnsStack StaticWebsite StaticWebsiteWithDns TarWebsite FatWebsite"
fi

for topo in $topos; do
  out="$OUTDIR/$topo.json"
  echo "Generating $out ..."
  dune exec -- ofpp fpv --topology "$topo" -o "$out" $FILES
done

echo "Done. FPV JSON files in $OUTDIR/"

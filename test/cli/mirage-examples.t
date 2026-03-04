MirageOS examples: generate main.ml from FPP topologies.

  $ F="../../examples/mirage"

Standalone app generates Unikernel module alias and start entry point
  $ ofpp to-ml --topologies UnixHello $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null | grep -E '(module App|App.start)'
  module App = Unikernel
  let app = lazy (App.start ())

All standalone topologies generate module alias and start call
  $ for t in UnixHello UnixHelloKey UnixClock UnixCrypto UnixHeads1 UnixHeads2 UnixTimeout1 UnixTimeout2 UnixEchoServer; do
  >   out=$(ofpp to-ml --topologies "$t" $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null)
  >   echo "$out" | grep -q 'App.start' && echo "$t: OK" || echo "$t: FAIL"
  > done
  UnixHello: OK
  UnixHelloKey: OK
  UnixClock: OK
  UnixCrypto: OK
  UnixHeads1: OK
  UnixHeads2: OK
  UnixTimeout1: OK
  UnixTimeout2: OK
  UnixEchoServer: OK

Block topologies generate connect calls with params
  $ for t in UnixBlock UnixDiskLottery; do
  >   out=$(ofpp to-ml --topologies "$t" $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null)
  >   echo "$out" | grep -q 'Ramdisk.connect' && echo "$t: OK" || echo "$t: FAIL"
  > done
  UnixBlock: OK
  UnixDiskLottery: OK

KV topology wires static store via functor
  $ ofpp to-ml --topologies UnixKvRo $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null | grep -E '(Static_t|Unikernel)'
  module Kv_store = Static_t
  module Kv_app = Unikernel.Main(Kv_store)

Entry points include Mirage_runtime boilerplate
  $ ofpp to-ml --topologies UnixHello $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null | grep -c 'Mirage_runtime'
  6

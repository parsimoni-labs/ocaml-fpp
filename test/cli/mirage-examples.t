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

Socket stack topologies use params for connect args
  $ ofpp to-ml --topologies UnixNetwork $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null | grep -E '(Stackv4v6|Udpv4v6|Tcpv4v6)' | head -5
  module Stackv4v6 = Tcpip_stack_socket.V4V6
  module Stack_app = Unikernel.Main(Stackv4v6)
    Udpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None)
    Tcpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None)
    Stackv4v6.connect udpv4v6_socket tcpv4v6_socket)

Dhcp topology uses Netif with positional device param
  $ ofpp to-ml --topologies UnixDhcp $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null | grep -E '(Netif|Net_app)'
  module Net_app = Unikernel.Main(Netif)
    Netif.connect (netif__device ()))
    Net_app.start netif)

Ping6 topology wires Ethernet and IPv6 functors
  $ ofpp to-ml --topologies UnixPing6 $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null | grep -E 'module (Eth|Ipv6|Ping6)'
  module Eth = Ethernet.Make(Netif)
  module Ipv6 = Ipv6.Make(Netif)(Eth)
  module Ping6_app = Unikernel.Main(Netif)(Eth)(Ipv6)

Entry points include Mirage_runtime boilerplate
  $ ofpp to-ml --topologies UnixHello $F/types.fpp $F/devices.fpp $F/stacks.fpp $F/applications.fpp 2>/dev/null | grep -c 'Mirage_runtime'
  6

MirageOS examples: generate main.ml from FPP topologies.

  $ F="../../examples/mirage"

Standalone app generates start entry point (no module alias needed)
  $ ofpp to-ml --topologies UnixHello $F/mirage.fpp $F/tutorial/hello/config.fpp 2>/dev/null
  $ grep -E 'Unikernel.start' main.ml
  let start = lazy (Unikernel.start ())

All standalone topologies generate start call
  $ for t in hello hello-key; do
  >   ofpp to-ml --topologies "$(grep -o 'Unix[A-Za-z]*' $F/tutorial/$t/config.fpp)" $F/mirage.fpp $F/tutorial/$t/config.fpp 2>/dev/null
  >   grep -q 'Unikernel.start' main.ml && echo "$t: OK" || echo "$t: FAIL"
  > done
  hello: OK
  hello-key: OK

Block topology generates connect call with port params
  $ ofpp to-ml --topologies UnixBlock $F/mirage.fpp $F/device-usage/block/config.fpp 2>/dev/null
  $ grep 'Ramdisk.connect' main.ml
    let* ramdisk = Ramdisk.connect ~name:"block-test" in

KV topology wires static store via functor
  $ ofpp to-ml --topologies UnixKvRo $F/mirage.fpp $F/device-usage/kv_ro/config.fpp 2>/dev/null
  $ grep -E '(Static_t|Unikernel)' main.ml
  module Unikernel = Unikernel.Main(Static_t)
    let* static_t = Static_t.connect () in
    Unikernel.start static_t)

Socket stack topologies use port params for connect args
  $ ofpp to-ml --topologies UnixNetwork $F/mirage.fpp $F/device-usage/network/config.fpp 2>/dev/null
  $ grep -E '(Stackv4v6|Udpv4v6|Tcpv4v6|Unikernel)' main.ml | head -5
  module Stackv4v6 = Stackv4v6.Make(Udpv4v6_socket)(Tcpv4v6_socket)
  module Unikernel = Unikernel.Main(Stackv4v6)
    let* udpv4v6_socket = Udpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None in
    let* tcpv4v6_socket = Tcpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None in
    Stackv4v6.connect udpv4v6_socket tcpv4v6_socket)

Dhcp topology uses Netif with positional device port param
  $ ofpp to-ml --topologies UnixDhcp $F/mirage.fpp $F/applications/dhcp/config.fpp 2>/dev/null
  $ grep -E '(Netif|Unikernel)' main.ml
  module Unikernel = Unikernel.Main(Netif)
    let* netif = Netif.connect "tap0" in
    Unikernel.start netif)

Ping6 topology wires Ethernet and IPv6 functors
  $ ofpp to-ml --topologies UnixPing6 $F/mirage.fpp $F/device-usage/ping6/config.fpp 2>/dev/null
  $ grep -E 'module (Eth|Ipv6|Unikernel)' main.ml
  module Ethernet = Ethernet.Make(Netif)
  module Ipv6 = Ipv6.Make(Netif)(Ethernet)
  module Unikernel = Unikernel.Main(Netif)(Ethernet)(Ipv6)

Conduit topology uses adapter with start method
  $ ofpp to-ml --topologies UnixConduit $F/mirage.fpp $F/device-usage/conduit_server/config.fpp 2>/dev/null
  $ grep -E '(Conduit_tcp|Unikernel)' main.ml
  module Conduit_tcp = Conduit_tcp.Make(Stackv4v6)
  module Unikernel = Unikernel.Main(Conduit_tcp)
    let* conduit_tcp = Conduit_tcp.start stackv4v6 in
    Unikernel.start conduit_tcp)

DNS topology uses adapter with start method
  $ ofpp to-ml --topologies UnixDns $F/mirage.fpp $F/applications/dns/config.fpp 2>/dev/null
  $ grep -E '(Dns_client|Happy_eyeballs|Unikernel)' main.ml
  module Happy_eyeballs_mirage = Happy_eyeballs_mirage.Make(Stackv4v6)
  module Dns_client = Dns_resolver.Make(Stackv4v6)(Happy_eyeballs_mirage)
  module Unikernel = Unikernel.Make(Dns_client)
    let* happy_eyeballs_mirage = Happy_eyeballs_mirage.connect_device stackv4v6 in
    let* dns_client = Dns_client.start stackv4v6 happy_eyeballs_mirage in
    Unikernel.start dns_client)

Entry points include Mirage_runtime boilerplate
  $ ofpp to-ml --topologies UnixHello $F/mirage.fpp $F/tutorial/hello/config.fpp 2>/dev/null
  $ grep -c 'Mirage_runtime' main.ml
  6

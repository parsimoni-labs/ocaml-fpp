MirageOS examples: generate main.ml from FPP topologies.

  $ F="../../examples/mirage"

Standalone app generates start entry point (no module alias needed)
  $ ofpp to-ml --topologies UnixHello $F/mirage.fpp 2>/dev/null
  $ grep -E 'Unikernel.start' main.ml
  let start = lazy (Unikernel.start ())

All standalone topologies generate start call
  $ for t in UnixHello UnixHelloKey UnixClock UnixCrypto UnixHeads1 UnixHeads2 UnixTimeout1 UnixTimeout2 UnixEchoServer; do
  >   ofpp to-ml --topologies "$t" $F/mirage.fpp 2>/dev/null
  >   grep -q 'Unikernel.start' main.ml && echo "$t: OK" || echo "$t: FAIL"
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

Block topologies generate connect calls with port params
  $ for t in UnixBlock UnixDiskLottery; do
  >   ofpp to-ml --topologies "$t" $F/mirage.fpp 2>/dev/null
  >   grep -q 'Ramdisk.connect ~name' main.ml && echo "$t: OK" || echo "$t: FAIL"
  > done
  UnixBlock: OK
  UnixDiskLottery: OK

KV topology wires static store via functor
  $ ofpp to-ml --topologies UnixKvRo $F/mirage.fpp 2>/dev/null
  $ grep -E '(Static_t|Unikernel)' main.ml
  module Kv_store = Static_t
  module Kv_app = Unikernel.Main(Kv_store)

Socket stack topologies use positional port params for connect args
  $ ofpp to-ml --topologies UnixNetwork $F/mirage.fpp 2>/dev/null
  $ grep -E '(Stackv4v6|Udpv4v6|Tcpv4v6)' main.ml | head -5
  module Stackv4v6 = Stackv4v6.Make(Udpv4v6_socket)(Tcpv4v6_socket)
  module Stack_app = Unikernel.Main(Stackv4v6)
    let* udpv4v6_socket = Udpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None in
    let* tcpv4v6_socket = Tcpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None in
    Stackv4v6.connect udpv4v6_socket tcpv4v6_socket)

Dhcp topology uses Netif with positional device port param
  $ ofpp to-ml --topologies UnixDhcp $F/mirage.fpp 2>/dev/null
  $ grep -E '(Netif|Net_app)' main.ml
  module Net_app = Unikernel.Main(Netif)
    let* netif = Netif.connect (netif__0 ()) in
    Net_app.start netif)

Ping6 topology wires Ethernet and IPv6 functors
  $ ofpp to-ml --topologies UnixPing6 $F/mirage.fpp 2>/dev/null
  $ grep -E 'module (Eth|Ipv6|Ping6)' main.ml
  module Ethernet = Ethernet.Make(Netif)
  module Ipv6 = Ipv6.Make(Netif)(Ethernet)
  module Ping6_app = Unikernel.Main(Netif)(Ethernet)(Ipv6)

Conduit topology uses adapter with start method
  $ ofpp to-ml --topologies UnixConduit $F/mirage.fpp 2>/dev/null
  $ grep -E '(Conduit_tcp|Conduit_app)' main.ml
  module Conduit_tcp = Conduit_tcp.Make(Stackv4v6)
  module Conduit_app = Unikernel.Main(Conduit_tcp)
    let* conduit_tcp = Conduit_tcp.start stackv4v6 in
    Conduit_app.start conduit_tcp)

DNS topology uses adapter with start method for tuple unpacking
  $ ofpp to-ml --topologies UnixDns $F/mirage.fpp 2>/dev/null
  $ grep -E '(Dns_client|Happy_eyeballs|Dns_client_app)' main.ml
  module Happy_eyeballs_mirage = Happy_eyeballs_mirage.Make(Stackv4v6)
  module Dns_client = Dns_resolver.Make(Stackv4v6)(Happy_eyeballs_mirage)
  module Dns_client_app = Unikernel.Make(Dns_client)
    let* happy_eyeballs_mirage = Happy_eyeballs_mirage.connect_device stackv4v6 in
    let* dns_client = Dns_client.start stackv4v6 happy_eyeballs_mirage in
    Dns_client_app.start dns_client)

DirectNetwork imports TcpipStack and generates 11 functor applications
  $ ofpp to-ml --topologies DirectNetwork $F/mirage.fpp 2>/dev/null
  $ grep -E '^module [A-Z]' main.ml
  module Net = Vnetif.Make(Backend)
  module Ethernet = Ethernet.Make(Net)
  module Arp = Arp.Make(Ethernet)
  module Ipv4 = Static_ipv4.Make(Ethernet)(Arp)
  module Ipv6 = Ipv6.Make(Net)(Ethernet)
  module Ip = Tcpip_stack_direct.IPV4V6(Ipv4)(Ipv6)
  module Icmp = Icmpv4.Make(Ipv4)
  module Udp = Udp.Make(Ip)
  module Tcp = Tcp.Flow.Make(Ip)
  module Stack = Tcpip_stack_direct.MakeV4V6(Net)(Ethernet)(Arp)(Ip)(Icmp)(Udp)(Tcp)
  module Stack_app = Unikernel.Main(Stack)

DirectNetwork uses params (not Runtime labelled args) for ipv4 and ip config
  $ ofpp to-ml --topologies DirectNetwork $F/mirage.fpp 2>/dev/null
  $ grep -E '(cidr|ipv4_only|ipv6_only)' main.ml | head -2
    let* ipv4 = Ipv4.connect ~cidr:(Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24") ethernet arp in
    let* ip = Ip.connect ~ipv4_only:false ~ipv6_only:false ipv4 ipv6 in

DirectNetwork has no runtime thunk calls (no tcpip_runtime references)
  $ ofpp to-ml --topologies DirectNetwork $F/mirage.fpp 2>/dev/null
  $ grep 'tcpip_runtime' main.ml || echo "none"
  none

Entry points include Mirage_runtime boilerplate
  $ ofpp to-ml --topologies UnixHello $F/mirage.fpp 2>/dev/null
  $ grep -c 'Mirage_runtime' main.ml
  6

@ MirageOS device catalogue and deployment topologies.

@ ── External types ──────────────────────────────────────

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ocaml.type Ipaddr.V4.t
type Ipv4Addr

@ ocaml.type Macaddr.t
type Macaddr

@ ── Port types ──────────────────────────────────────────

struct SocketRequired {
  ipv4Cidr: Cidr,
  ipv6Cidr: string
}

struct SocketOptional {
  ipv4Only: bool,
  ipv6Only: bool
} default { ipv4Only = false, ipv6Only = false }

port SocketConnect(required: SocketRequired, optional: SocketOptional)

struct BlockConfig {
  name: string
} default { name = "disk" }

port BlockConnect(config: BlockConfig)

struct NetifConfig {
  device: string
} default { device = "tap0" }

port NetifConnect(config: NetifConfig)

struct Ipv4Required {
  cidr: Cidr
}

struct Ipv4Optional {
  gateway: Ipv4Addr
}

port Ipv4Connect(required: Ipv4Required, optional: Ipv4Optional)

struct IpOptional {
  ipv4Only: bool,
  ipv6Only: bool
} default { ipv4Only = false, ipv6Only = false }

port IpConnect(optional: IpOptional)

@ ── Interfaces and components ───────────────────────────
@
@ Interfaces model OCaml module types. The FPP qualified name
@ maps directly to the OCaml module type path. Components
@ import interfaces to declare which sig they satisfy.
@ Components that import an interface inherit its ports.

module Vnetif {
  interface BACKEND {
    sync input port connect: serial
  }

  passive component Make {
    import Mirage_net.S
    output port backend: serial
  }
}

module Mirage_block {
  interface S {
    sync input port connect: serial
  }
}

module Mirage_kv {
  interface RO {
    sync input port connect: serial
  }
}

module Mirage_net {
  interface S {
    sync input port connect: serial
  }
}

module Tcpip {
  module Udp {
    interface S {
      sync input port connect: serial
    }
  }
  module Tcp {
    interface S {
      sync input port connect: serial
    }
  }
  module Ip {
    interface S {
      sync input port connect: serial
    }
  }
  module Stack {
    interface V4V6 {
      sync input port connect: serial
    }
  }
}

module Ethernet {
  interface S {
    sync input port connect: serial
  }

  passive component Make {
    import Ethernet.S
    output port net: serial
  }
}

module Arp {
  interface S {
    sync input port connect: serial
  }

  passive component Make {
    import Arp.S
    output port eth: serial
  }
}

module Icmpv4 {
  interface S {
    sync input port connect: serial
  }

  passive component Make {
    import Icmpv4.S
    output port ip: serial
  }
}

module Conduit_mirage {
  interface S {
    sync input port connect: serial
  }

  passive component TLS {
    import Conduit_mirage.S
    output port conduit: serial
  }
}

module Cohttp_mirage {
  module Server {
    interface S {
      sync input port connect: serial
    }

    passive component Make {
      import Cohttp_mirage.Server.S
      output port conduit: serial
    }
  }
}

module Happy_eyeballs_mirage {
  interface S {
    sync input port connect: serial
  }

  passive component Make {
    import Happy_eyeballs_mirage.S
    sync input port connect_device: serial
    output port stack: serial
  }
}

module Dns_client_mirage {
  interface S {
    sync input port connect: serial
  }
}

@ ── Leaf devices ────────────────────────────────────────

passive component Backend {
  import Vnetif.BACKEND
}

passive component Block {
  import Mirage_block.S
  sync input port connect: BlockConnect
}

passive component Kv {
  import Mirage_kv.RO
}

passive component Netif {
  import Mirage_net.S
  sync input port connect: NetifConnect
}

@ ── Socket devices ──────────────────────────────────────

passive component Udpv4v6_socket {
  import Tcpip.Udp.S
  sync input port connect: SocketConnect
}

passive component Tcpv4v6_socket {
  import Tcpip.Tcp.S
  sync input port connect: SocketConnect
}

module Stackv4v6 {
  passive component Make {
    import Tcpip.Stack.V4V6
    output port udp: serial
    output port tcp: serial
  }
}

@ ── Block-backed KV store ───────────────────────────────

passive component Block_kv {
  import Mirage_kv.RO
  output port block: serial
}

@ ── Protocol stack ──────────────────────────────────────

module Static_ipv4 {
  passive component Make {
    import Tcpip.Ip.S
    sync input port connect: Ipv4Connect
    output port eth: serial
    output port arp: serial
  }
}

module Ipv6 {
  passive component Make {
    import Tcpip.Ip.S
    output port net: serial
    output port eth: serial
  }
}

module Tcpip_stack_direct {
  passive component IPV4V6 {
    import Tcpip.Ip.S
    sync input port connect: IpConnect
    output port ipv4: serial
    output port ipv6: serial
  }

  passive component MakeV4V6 {
    import Tcpip.Stack.V4V6
    output port netif: serial
    output port ethernet: serial
    output port arpv4: serial
    output port ipv4v6: serial
    output port icmpv4: serial
    output port udpv4v6: serial
    output port tcpv4v6: serial
  }
}

module Udp {
  passive component Make {
    import Tcpip.Udp.S
    output port ip: serial
  }
}

module Tcp {
  module Flow {
    passive component Make {
      import Tcpip.Tcp.S
      output port ip: serial
    }
  }
}

@ ── Conduit / TLS / CoHTTP ──────────────────────────────

module Conduit_tcp {
  passive component Make {
    import Conduit_mirage.S
    sync input port start: serial
    output port stack: serial
  }
}

@ ── DNS ─────────────────────────────────────────────────

module Dns_resolver {
  passive component Make {
    import Dns_client_mirage.S
    sync input port start: serial
    output port stack: serial
    output port happy_eyeballs: serial
  }
}

@ ── Application components ──────────────────────────────

passive component StandaloneApp { sync input port start: serial }

passive component BlockApp {
  sync input port start: serial
  output port block: serial
}

passive component KvRoApp {
  sync input port start: serial
  output port kv: serial
}

passive component StackApp {
  sync input port start: serial
  output port stack: serial
}

passive component DnsClientApp {
  sync input port start: serial
  output port dns: serial
}

passive component NetApp {
  sync input port start: serial
  output port net: serial
}

passive component Ping6App {
  sync input port start: serial
  output port net: serial
  output port eth: serial
  output port ipv6: serial
}

passive component ConduitApp {
  sync input port start: serial
  output port conduit: serial
}

@ ── Device instances ────────────────────────────────────

instance backend: Backend base id 0
instance net: Vnetif.Make base id 0
instance udpv4v6_socket: Udpv4v6_socket base id 0
instance tcpv4v6_socket: Tcpv4v6_socket base id 0
instance stackv4v6: Stackv4v6.Make base id 0
instance ethernet: Ethernet.Make base id 0
instance arp: Arp.Make base id 0
instance ipv4: Static_ipv4.Make base id 0
instance ipv6: Ipv6.Make base id 0
instance ip: Tcpip_stack_direct.IPV4V6 base id 0
instance icmp: Icmpv4.Make base id 0
instance udp: Udp.Make base id 0
instance tcp: Tcp.Flow.Make base id 0
instance stack: Tcpip_stack_direct.MakeV4V6 base id 0
instance data: Kv base id 0
instance certs: Kv base id 0
instance htdocs_data: Kv base id 0
instance tls_data: Kv base id 0
instance data_block: Block base id 0
instance certs_block: Block base id 0
@ ocaml.module Tar_mirage.Make_KV_RO
instance tar_data: Block_kv base id 0
@ ocaml.module Tar_mirage.Make_KV_RO
instance tar_certs: Block_kv base id 0
@ ocaml.module Fat.KV_RO
instance fat_data: Block_kv base id 0
@ ocaml.module Fat.KV_RO
instance fat_certs: Block_kv base id 0
instance happy_eyeballs_mirage: Happy_eyeballs_mirage.Make base id 0
instance dns_client: Dns_resolver.Make base id 0

@ ── Application instances ───────────────────────────────

instance unikernel: StandaloneApp base id 0
instance block_app: BlockApp base id 0
instance kv_app: KvRoApp base id 0
instance stack_app: StackApp base id 0
instance dns_client_app: DnsClientApp base id 0
instance net_app: NetApp base id 0
instance ping6_app: Ping6App base id 0
instance conduit_app: ConduitApp base id 0
instance ramdisk: Block base id 0
instance kv_store: Kv base id 0
instance conduit_tcp: Conduit_tcp.Make base id 0
instance netif: Netif base id 0

@ ── Sub-topologies ──────────────────────────────────────

topology TcpipStack {
  instance backend
  instance net
  instance ethernet
  instance arp
  @ ocaml.param cidr (Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24")
  instance ipv4
  instance ipv6
  @ ocaml.param ipv4_only false
  @ ocaml.param ipv6_only false
  instance ip
  instance icmp
  instance udp
  instance tcp
  instance stack

  connections Connect {
    net.backend -> backend.connect
    ethernet.net -> net.connect
    arp.eth -> ethernet.connect
    ipv4.eth -> ethernet.connect
    ipv4.arp -> arp.connect
    ipv6.net -> net.connect
    ipv6.eth -> ethernet.connect
    ip.ipv4 -> ipv4.connect
    ip.ipv6 -> ipv6.connect
    icmp.ip -> ipv4.connect
    udp.ip -> ip.connect
    tcp.ip -> ip.connect
    stack.netif -> net.connect
    stack.ethernet -> ethernet.connect
    stack.arpv4 -> arp.connect
    stack.ipv4v6 -> ip.connect
    stack.icmpv4 -> icmp.connect
    stack.udpv4v6 -> udp.connect
    stack.tcpv4v6 -> tcp.connect
  }
}

topology SocketStack {
  @ ocaml.param ipv4_only false
  @ ocaml.param ipv6_only false
  @ ocaml.param ipv4_cidr (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0")
  @ ocaml.param ipv6_cidr None
  instance udpv4v6_socket
  @ ocaml.param ipv4_only false
  @ ocaml.param ipv6_only false
  @ ocaml.param ipv4_cidr (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0")
  @ ocaml.param ipv6_cidr None
  instance tcpv4v6_socket
  instance stackv4v6

  connections Connect {
    stackv4v6.udp -> udpv4v6_socket.connect
    stackv4v6.tcp -> tcpv4v6_socket.connect
  }
}

topology DnsStack {
  instance happy_eyeballs_mirage
  instance dns_client

  connections Start {
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
  }
}

@ ── Deployment topologies ───────────────────────────────

topology UnixHello {
  instance unikernel
}

topology UnixHelloKey {
  instance unikernel
}

topology UnixClock {
  instance unikernel
}

topology UnixCrypto {
  instance unikernel
}

topology UnixHeads1 {
  instance unikernel
}

topology UnixHeads2 {
  instance unikernel
}

topology UnixTimeout1 {
  instance unikernel
}

topology UnixTimeout2 {
  instance unikernel
}

topology UnixEchoServer {
  instance unikernel
}

topology UnixBlock {
  @ ocaml.param name "block-test"
  instance ramdisk
  @ ocaml.module Unikernel.Main
  instance block_app

  connections Start {
    block_app.block -> ramdisk.connect
  }
}

topology UnixDiskLottery {
  @ ocaml.param name "lottery-disk"
  instance ramdisk
  @ ocaml.module Unikernel.Main
  instance block_app

  connections Start {
    block_app.block -> ramdisk.connect
  }
}

topology UnixKvRo {
  @ ocaml.module Static_t
  instance kv_store
  @ ocaml.module Unikernel.Main
  instance kv_app

  connections Start {
    kv_app.kv -> kv_store.connect
  }
}

topology UnixNetwork {
  import SocketStack
  instance stackv4v6
  @ ocaml.module Unikernel.Main
  instance stack_app

  connections Start {
    stack_app.stack -> stackv4v6.connect
  }
}

topology UnixConduit {
  import SocketStack
  instance stackv4v6
  instance conduit_tcp
  @ ocaml.module Unikernel.Main
  instance conduit_app

  connections Start {
    conduit_tcp.stack -> stackv4v6.connect
    conduit_app.conduit -> conduit_tcp.start
  }
}

topology UnixDns {
  import SocketStack
  instance stackv4v6
  instance happy_eyeballs_mirage
  instance dns_client
  @ ocaml.module Unikernel.Make
  instance dns_client_app

  connections Connect_device {
    happy_eyeballs_mirage.stack -> stackv4v6.connect
  }

  connections Start {
    dns_client.stack -> stackv4v6.connect
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
    dns_client_app.dns -> dns_client.start
  }
}

topology UnixDhcp {
  instance netif
  @ ocaml.module Unikernel.Main
  instance net_app

  connections Start {
    net_app.net -> netif.connect
  }
}

topology UnixPing6 {
  instance netif
  instance ethernet
  instance ipv6
  @ ocaml.module Unikernel.Main
  instance ping6_app

  connections Connect {
    ethernet.net -> netif.connect
    ipv6.net -> netif.connect
    ipv6.eth -> ethernet.connect
  }

  connections Start {
    ping6_app.net -> netif.connect
    ping6_app.eth -> ethernet.connect
    ping6_app.ipv6 -> ipv6.connect
  }
}

topology DirectNetwork {
  import TcpipStack
  @ ocaml.module Backend
  instance backend
  @ ocaml.module Unikernel.Main
  instance stack_app

  connections Start {
    stack_app.stack -> stack.connect
  }
}

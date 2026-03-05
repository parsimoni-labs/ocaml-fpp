@ MirageOS device catalogue and deployment topologies.

@ External types

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ocaml.type Ipaddr.V4.t
type Ipv4Addr

@ Leaf devices

@ ocaml.sig Vnetif.BACKEND
passive component Backend { sync input port connect }

@ ocaml.sig Mirage_block.S
passive component Block {
  param name: string default "disk"
  sync input port connect
}

@ ocaml.sig Mirage_kv.RO
passive component Kv { sync input port connect }

@ ocaml.sig Mirage_net.S
passive component Netif {
  @ ocaml.positional
  param device: string default "tap0"
  sync input port connect
}

@ Socket devices

@ ocaml.sig Tcpip.Udp.S
passive component Udpv4v6_socket {
  param ipv4Only: bool default false
  param ipv6Only: bool default false
  @ ocaml.positional
  param ipv4Cidr: string
  @ ocaml.positional
  param ipv6Cidr: string
  sync input port connect
}

@ ocaml.sig Tcpip.Tcp.S
passive component Tcpv4v6_socket {
  param ipv4Only: bool default false
  param ipv6Only: bool default false
  @ ocaml.positional
  param ipv4Cidr: string
  @ ocaml.positional
  param ipv6Cidr: string
  sync input port connect
}

module Stackv4v6 {
  @ ocaml.sig Tcpip.Stack.V4V6
  passive component Make {
    sync input port connect
    output port udp
    output port tcp
  }
}

@ Network

module Vnetif {
  @ ocaml.sig Mirage_net.S
  passive component Make {
    sync input port connect
    output port backend
  }
}

@ Block-backed KV store

@ ocaml.sig Mirage_kv.RO
passive component Block_kv {
  sync input port connect
  output port block
}

@ Protocol stack

module Ethernet {
  @ ocaml.sig Ethernet.S
  passive component Make {
    sync input port connect
    output port net
  }
}

module Arp {
  @ ocaml.sig Arp.S
  passive component Make {
    sync input port connect
    output port eth
  }
}

module Static_ipv4 {
  @ ocaml.sig Tcpip.Ip.S
  passive component Make {
    param cidr: Cidr
    @ ocaml.optional
    param gateway: Ipv4Addr
    sync input port connect
    output port eth
    output port arp
  }
}

module Ipv6 {
  @ ocaml.sig Tcpip.Ip.S
  passive component Make {
    sync input port connect
    output port net
    output port eth
  }
}

module Tcpip_stack_direct {
  @ ocaml.sig Tcpip.Ip.S
  passive component IPV4V6 {
    param ipv4Only: bool default false
    param ipv6Only: bool default false
    sync input port connect
    output port ipv4
    output port ipv6
  }

  @ ocaml.sig Tcpip.Stack.V4V6
  passive component MakeV4V6 {
    sync input port connect
    output port netif
    output port ethernet
    output port arpv4
    output port ipv4v6
    output port icmpv4
    output port udpv4v6
    output port tcpv4v6
  }
}

module Icmpv4 {
  @ ocaml.sig Icmpv4.S
  passive component Make {
    sync input port connect
    output port ip
  }
}

module Udp {
  @ ocaml.sig Tcpip.Udp.S
  passive component Make {
    sync input port connect
    output port ip
  }
}

module Tcp {
  module Flow {
    @ ocaml.sig Tcpip.Tcp.S
    passive component Make {
      sync input port connect
      output port ip
    }
  }
}

@ Conduit / TLS / CoHTTP

module Conduit_tcp {
  @ ocaml.sig Conduit_mirage.S
  passive component Make {
    sync input port start
    output port stack
  }
}

module Conduit_mirage {
  @ ocaml.sig Conduit_mirage.S
  passive component TLS {
    sync input port connect
    output port conduit
  }
}

module Cohttp_mirage {
  module Server {
    @ ocaml.sig Cohttp_mirage.Server.S
    passive component Make {
      sync input port connect
      output port conduit
    }
  }
}

@ DNS

module Happy_eyeballs_mirage {
  @ ocaml.sig Happy_eyeballs_mirage.S
  passive component Make {
    sync input port connect_device
    output port stack
  }
}

module Dns_resolver {
  @ ocaml.sig Dns_client_mirage.S
  passive component Make {
    sync input port start
    output port stack
    output port happy_eyeballs
  }
}

@ Application components

passive component StandaloneApp { sync input port start }

passive component BlockApp {
  sync input port start
  output port block
}

passive component KvRoApp {
  sync input port start
  output port kv
}

passive component StackApp {
  sync input port start
  output port stack
}

passive component DnsClientApp {
  sync input port start
  output port dns
}

passive component NetApp {
  sync input port start
  output port net
}

passive component Ping6App {
  sync input port start
  output port net
  output port eth
  output port ipv6
}

passive component ConduitApp {
  sync input port start
  output port conduit
}

@ Device instances

instance backend: Backend base id 0x050
instance net: Vnetif.Make base id 0x100
instance udpv4v6_socket: Udpv4v6_socket base id 0xD00
instance tcpv4v6_socket: Tcpv4v6_socket base id 0xD10
instance stackv4v6: Stackv4v6.Make base id 0xD20
instance ethernet: Ethernet.Make base id 0x200
instance arp: Arp.Make base id 0x300
instance ipv4: Static_ipv4.Make base id 0x400
instance ipv6: Ipv6.Make base id 0x450
instance ip: Tcpip_stack_direct.IPV4V6 base id 0x460
instance icmp: Icmpv4.Make base id 0x500
instance udp: Udp.Make base id 0x600
instance tcp: Tcp.Flow.Make base id 0x700
instance stack: Tcpip_stack_direct.MakeV4V6 base id 0xC00
instance data: Kv base id 0x800
instance certs: Kv base id 0x900
instance htdocs_data: Kv base id 0x870
instance tls_data: Kv base id 0x880
instance data_block: Block base id 0x810
instance certs_block: Block base id 0x820
@ ocaml.module Tar_mirage.Make_KV_RO
instance tar_data: Block_kv base id 0x830
@ ocaml.module Tar_mirage.Make_KV_RO
instance tar_certs: Block_kv base id 0x840
@ ocaml.module Fat.KV_RO
instance fat_data: Block_kv base id 0x850
@ ocaml.module Fat.KV_RO
instance fat_certs: Block_kv base id 0x860
instance happy_eyeballs_mirage: Happy_eyeballs_mirage.Make base id 0xE00
instance dns_client: Dns_resolver.Make base id 0xE10

@ Application instances

instance unikernel: StandaloneApp base id 0x5000
instance block_app: BlockApp base id 0x5100
instance kv_app: KvRoApp base id 0x5200
instance stack_app: StackApp base id 0x5300
instance dns_client_app: DnsClientApp base id 0x5400
instance net_app: NetApp base id 0x5500
instance ping6_app: Ping6App base id 0x5600
instance conduit_app: ConduitApp base id 0x5700
instance ramdisk: Block base id 0x6000
instance kv_store: Kv base id 0x6100
instance conduit_tcp: Conduit_tcp.Make base id 0x6200
instance netif: Netif base id 0x6300

@ Sub-topologies

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

@ Deployment topologies

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

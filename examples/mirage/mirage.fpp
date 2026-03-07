@ MirageOS device catalogue and deployment topologies.
@
@ This file models the MirageOS device graph using native FPP constructs.
@ Each device category has an interface (OCaml module type), concrete
@ components (OCaml functors), and port types encoding connect signatures.
@
@ Mapping to targets:
@   port param (named)  → OCaml: ~label:v      C++: named arg
@   port param (_N)     → OCaml: positional     C++: positional
@   struct-typed param  → OCaml: expand fields  C++: expand fields
@   struct field w/ def → OCaml: optional label C++: has default
@   output port + conn  → OCaml: functor arg   C++: dep injection
@   external param      → OCaml: Cmdliner term C++: runtime config
@   instance(p = v)     → OCaml: inline value  C++: compile-time const

@ ── External types ──────────────────────────────────────

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ocaml.type Ipaddr.V4.t
type Ipv4Addr

@ ocaml.type Ipaddr.V6.Prefix.t
type Cidr6

@ ocaml.type Ipaddr.V6.t
type Ipv6Addr

@ ocaml.type Macaddr.t
type Macaddr

@ ── F Prime built-in port types ────────────────────────

module Fw {
  port PrmGet
  port PrmSet
}

@ ── Port types (connect signatures) ───────────────────
@
@ Named params → labeled (~name:value).
@ _N prefix → positional args.
@ Struct-typed params → expand as labeled fields; fields with defaults
@   become optional labels.

port SocketConnect(ipv4Only: bool, ipv6Only: bool, _0: Cidr, _1: Cidr6)

port BlockConnect(name: string)

port NetifConnect(_0: string)

port Ipv4Connect(cidr: Cidr)

@ Struct with defaults → optional labeled args.
struct Ipv6Conf { noInit: bool } default { noInit = false }
port Ipv6Connect(conf: Ipv6Conf)

port IpConnect(ipv4Only: bool, ipv6Only: bool)

port HttpServerConnect($port: U16)

port ChamelonConnect(programBlockSize: U32)

@ ══════════════════════════════════════════════════════
@ Infrastructure devices
@ ══════════════════════════════════════════════════════

module Mirage_sleep {
  interface S { sync input port connect: serial }
}

module Mirage_ptime {
  interface S { sync input port connect: serial }
}

module Mirage_mtime {
  interface S { sync input port connect: serial }
}

module Mirage_crypto_rng {
  interface S { sync input port connect: serial }
}

module Mirage_logs {
  interface S { sync input port connect: serial }
}

@ ══════════════════════════════════════════════════════
@ Block devices
@ ══════════════════════════════════════════════════════

module Mirage_block {
  interface S {
    sync input port connect: serial
  }
}

@ Block device backed by a file.
passive component Block {
  import Mirage_block.S
  sync input port connect: BlockConnect
}

@ In-memory block device (ramdisk).
passive component Ramdisk {
  import Mirage_block.S
  sync input port connect: BlockConnect
}

@ AES-CCM encrypted block device layer.
passive component Ccm_block {
  import Mirage_block.S
  external param key: string
  param get port prmGetOut
  param set port prmSetOut
  output port block: serial
}

@ ══════════════════════════════════════════════════════
@ Key/value stores
@ ══════════════════════════════════════════════════════

module Mirage_kv {
  interface RO {
    sync input port connect: serial
  }
  interface RW {
    sync input port connect: serial
  }
}

@ Static KV store (ocaml-crunch, embedded at build time).
passive component Crunch {
  import Mirage_kv.RO
}

@ Direct filesystem access (Unix only).
passive component Direct_kv_ro {
  import Mirage_kv.RO
  sync input port connect: BlockConnect
}

@ Opaque leaf KV (e.g. Static_t, for use with @ ocaml.module).
passive component Kv {
  import Mirage_kv.RO
}

@ Block-backed read-only KV (tar, fat).
passive component Block_kv {
  import Mirage_kv.RO
  output port block: serial
}

@ Direct filesystem access (Unix only, read-write).
passive component Direct_kv_rw {
  import Mirage_kv.RW
  sync input port connect: BlockConnect
}

@ In-memory read-write KV store.
passive component Kv_rw_mem {
  import Mirage_kv.RW
}

@ Chamelon (littlefs) read-write filesystem on a block device.
passive component Chamelon {
  import Mirage_kv.RW
  sync input port connect: ChamelonConnect
  output port block: serial
}

@ Tar archive read-write KV on a block device.
passive component Tar_kv_rw {
  import Mirage_kv.RW
  output port block: serial
}

@ ══════════════════════════════════════════════════════
@ Network interfaces
@ ══════════════════════════════════════════════════════

module Mirage_net {
  interface S {
    sync input port connect: serial
  }
}

@ Network backend (e.g. vnetif for testing).
module Vnetif {
  interface BACKEND {
    sync input port connect: serial
  }

  passive component Make {
    import Mirage_net.S
    output port backend: serial
  }
}

@ Host network interface.
passive component Netif {
  import Mirage_net.S
  sync input port connect: NetifConnect
}

passive component Backend {
  import Vnetif.BACKEND
}

@ ══════════════════════════════════════════════════════
@ Ethernet
@ ══════════════════════════════════════════════════════

module Ethernet {
  interface S {
    sync input port connect: serial
  }

  passive component Make {
    import Ethernet.S
    output port net: serial
  }
}

@ ══════════════════════════════════════════════════════
@ ARP
@ ══════════════════════════════════════════════════════

module Arp {
  interface S {
    sync input port connect: serial
  }

  passive component Make {
    import Arp.S
    output port eth: serial
  }
}

@ ══════════════════════════════════════════════════════
@ ICMP
@ ══════════════════════════════════════════════════════

module Icmpv4 {
  interface S {
    sync input port connect: serial
  }

  passive component Make {
    import Icmpv4.S
    output port ip: serial
  }
}

@ ══════════════════════════════════════════════════════
@ IP / TCP / UDP
@ ══════════════════════════════════════════════════════

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
    sync input port connect: Ipv6Connect
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

@ ── Socket-backed transport ───────────────────────────

passive component Udpv4v6_socket {
  import Tcpip.Udp.S
  sync input port connect: SocketConnect
}

passive component Tcpv4v6_socket {
  import Tcpip.Tcp.S
  sync input port connect: SocketConnect
}

module Stackv4v6 {
  @ Socket-backed stack (udp + tcp deps).
  passive component Make {
    import Tcpip.Stack.V4V6
    output port udp: serial
    output port tcp: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Conduit / TLS
@ ══════════════════════════════════════════════════════

module Conduit_mirage {
  interface S {
    sync input port connect: serial
  }

  passive component TLS {
    import Conduit_mirage.S
    output port conduit: serial
  }
}

module Conduit_tcp {
  passive component Make {
    import Conduit_mirage.S
    sync input port start: serial
    output port stack: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Happy Eyeballs + DNS
@ ══════════════════════════════════════════════════════

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

module Dns_resolver {
  passive component Make {
    import Dns_client_mirage.S
    sync input port start: serial
    output port stack: serial
    output port happy_eyeballs: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Mimic (protocol-agnostic connection layer)
@ ══════════════════════════════════════════════════════

module Mimic {
  interface S {
    sync input port connect: serial
  }

  @ mimic_happy_eyeballs : stackv4v6 -> happy_eyeballs -> dns_client -> mimic
  passive component Make {
    import Mimic.S
    output port stack: serial
    output port happy_eyeballs: serial
    output port dns: serial
  }
}

@ ══════════════════════════════════════════════════════
@ HTTP
@ ══════════════════════════════════════════════════════

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

module Paf_mirage {
  interface S {
    sync input port connect: serial
  }

  @ paf_server : ~port:int runtime_arg -> tcpv4v6 -> http_server
  passive component Server {
    import Paf_mirage.S
    sync input port connect: HttpServerConnect
    output port tcp: serial
  }
}

module Http_mirage_client {
  interface S {
    sync input port connect: serial
  }

  @ paf_client : tcpv4v6 -> mimic -> alpn_client
  passive component Make {
    import Http_mirage_client.S
    output port tcp: serial
    output port mimic: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Syslog
@ ══════════════════════════════════════════════════════

module Syslog {
  interface S {
    sync input port connect: serial
  }

  @ syslog_udp : stackv4v6 -> syslog
  passive component Udp {
    import Syslog.S
    output port stack: serial
  }

  @ syslog_tcp : stackv4v6 -> syslog
  passive component Tcp {
    import Syslog.S
    output port stack: serial
  }

  @ syslog_tls : stackv4v6 -> kv_ro -> syslog
  passive component Tls {
    import Syslog.S
    output port stack: serial
    output port certs: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Git client
@ ══════════════════════════════════════════════════════

module Git_mirage {
  interface S {
    sync input port connect: serial
  }

  @ git_tcp : tcpv4v6 -> mimic -> git_client
  passive component Tcp {
    import Git_mirage.S
    output port tcp: serial
    output port mimic: serial
  }

  @ git_ssh : tcpv4v6 -> mimic -> git_client
  @ (authenticator, key, password are runtime secrets)
  passive component Ssh {
    import Git_mirage.S
    external param authenticator: string default ""
    external param key: string default ""
    external param password: string default ""
    param get port prmGetOut
    param set port prmSetOut
    output port tcp: serial
    output port mimic: serial
  }

  @ git_http : tcpv4v6 -> mimic -> git_client
  passive component Http {
    import Git_mirage.S
    external param authenticator: string default ""
    param get port prmGetOut
    param set port prmSetOut
    output port tcp: serial
    output port mimic: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Device instances (shared by sub-topologies)
@ ══════════════════════════════════════════════════════

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
instance conduit_tcp: Conduit_tcp.Make base id 0
instance netif: Netif base id 0

@ ══════════════════════════════════════════════════════
@ Sub-topologies
@ ══════════════════════════════════════════════════════

topology TcpipStack {
  instance backend
  instance net
  instance ethernet
  instance arp
  instance ipv4(cidr = "10.0.0.2/24")
  instance ipv6
  instance ip(ipv4Only = false, ipv6Only = false)
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
  instance udpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
  instance tcpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
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


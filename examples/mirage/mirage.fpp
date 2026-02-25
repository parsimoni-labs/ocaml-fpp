@ MirageOS device catalogue and topologies.
@
@ Components mirror the MirageOS functor hierarchy.  Output ports
@ declare dependencies; the connection graph determines functor
@ application order and connect call arguments.

@ ── External types ─────────────────────────────────────────

@ ocaml.type Cstruct.t
type Buffer

type Macaddr

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ── Port types ─────────────────────────────────────────────
@
@ Each port type models an operation that a component provides
@ or consumes.  The generated module type maps input ports to
@ [val] declarations; output ports determine functor wiring.

port NetWrite(data: Buffer)
port NetListen(header_size: U32)
port MacAddr -> Macaddr
port Mtu -> U32
port Disconnect
port EthWrite(dst: Macaddr, payload: Buffer)
port ArpQuery(ip: Macaddr) -> Macaddr
port IpWrite(dst: string, payload: Buffer)
port IpConfig(prefix: Cidr)
port KvGet(key: string) -> string
port KvExists(key: string) -> bool
port KvList(key: string) -> string
port KvDigest(key: string) -> string
port HttpConn(uri: string)

@ A dependency-only port: declares a functor argument without
@ implying data flow.
port Dep

@ ── Network backend ──────────────────────────────────────

@ The leaf parameter for the virtual network switch.
@ For deployment, swap [Basic_backend.Make] with the
@ target backend (solo5, xen, unix tap).

@ ocaml.sig Vnetif.BACKEND
active component Backend {
  sync input port provide: Dep
}

@ ── Socket stack ────────────────────────────────────────

@ A pre-built OS socket stack for Unix targets.

@ ocaml.sig Tcpip.Stack.V4V6
active component SocketStack {
  sync input port provide: Dep
}

@ ── Network device ───────────────────────────────────────

@ ocaml.functor Vnetif.Make
active component Net {
  output port backend: Dep
  sync input port disconnect: Disconnect
  sync input port write: NetWrite
  sync input port listen: NetListen
  sync input port mac: MacAddr
  sync input port mtu: Mtu
}

@ ── Key-value stores ─────────────────────────────────────

@ ocaml.sig Mirage_kv.RO
active component Kv {
  sync input port disconnect: Disconnect
  sync input port get: KvGet
  sync input port exists: KvExists
  sync input port list: KvList
  sync input port digest: KvDigest
}

@ ── Protocol stack ───────────────────────────────────────
@
@ Convention: when a component's name matches the OCaml module
@ (e.g. Arp -> Arp.Make), no [@ ocaml.functor] is needed.

active component Ethernet {
  output port net_write: NetWrite
  sync input port write: EthWrite
}

active component Arp {
  output port eth_write: EthWrite
  sync input port query: ArpQuery
}

@ ocaml.functor Static_ipv4.Make
active component Ipv4 {
  output port eth_write: EthWrite
  output port arp_query: ArpQuery
  sync input port write: IpWrite
  @ ocaml.param
  sync input port cidr: IpConfig
}

active component Ipv6 {
  output port net_write: NetWrite
  output port eth_write: EthWrite
}

@ ocaml.functor Tcpip_stack_direct.IPV4V6
@ ocaml.connect_args ~ipv4_only:true ~ipv6_only:false
active component Ip {
  output port ipv4: IpWrite
  output port ipv6: IpWrite
  sync input port write: IpWrite
}

@ ocaml.functor Icmpv4.Make
active component Icmp {
  output port ip_write: IpWrite
}

active component Udp {
  output port ip_write: IpWrite
}

@ ocaml.functor Tcp.Flow.Make
active component Tcp {
  output port ip_write: IpWrite
  sync input port write: IpWrite
}

@ ── Stack assembly ───────────────────────────────────────
@
@ Wraps all protocol layers into one [Tcpip.Stack.V4V6].
@ Output ports list functor dependencies; [connect] takes
@ all seven and starts the packet input loop internally.

@ ocaml.functor Tcpip_stack_direct.MakeV4V6
active component TcpipStack {
  sync input port provide: Dep
  output port netif: Dep
  output port ethernet: Dep
  output port arpv4: Dep
  output port ipv4v6: Dep
  output port icmpv4: Dep
  output port udpv4v6: Dep
  output port tcpv4v6: Dep
}

@ ── Conduit transport ────────────────────────────────────
@
@ Conduit unifies TLS and plain TCP under one flow type,
@ letting a single CoHTTP server handle both HTTPS and
@ HTTP redirect without separate modules per transport.

@ ocaml.functor Conduit_mirage.TCP
passive component Conduit_tcp {
  output port stack: Dep
  sync input port connect: Dep
}

@ ocaml.functor Conduit_mirage.TLS
passive component Conduit {
  output port transport: Dep
  sync input port connect: Dep
}

@ ocaml.functor Cohttp_mirage.Server.Make
passive component Http {
  output port conduit: Dep
  sync input port listen: HttpConn
}

@ ── Instances ────────────────────────────────────────────

instance backend: Backend base id 0x050
instance net: Net base id 0x100
instance eth: Ethernet base id 0x200
instance arp: Arp base id 0x300
instance ipv4: Ipv4 base id 0x400
instance ipv6: Ipv6 base id 0x450
instance ip: Ip base id 0x460
instance icmp: Icmp base id 0x500
instance udp: Udp base id 0x600
instance tcp: Tcp base id 0x700
instance data: Kv base id 0x800
instance certs: Kv base id 0x900
instance conduit_tcp: Conduit_tcp base id 0xA00
instance conduit: Conduit base id 0xA10
instance http: Http base id 0xA20
instance stack: TcpipStack base id 0xC00
instance socket_stack: SocketStack base id 0xD00

@ ── Topologies ───────────────────────────────────────────
@
@ Sub-topologies are composed via [import]; the parent topology
@ provides any missing connections (e.g. which stack to use).

@ Protocol stack: backend through [MakeV4V6].
topology TcpipStack {
  instance backend
  instance net
  instance eth
  instance arp
  instance ipv4
  instance ipv6
  instance ip
  instance icmp
  instance udp
  instance tcp
  instance stack

  connections Connect {
    net.backend -> backend.provide
    eth.net_write -> net.write
    arp.eth_write -> eth.write
    ipv4.eth_write -> eth.write
    ipv4.arp_query -> arp.query
    ipv6.net_write -> net.write
    ipv6.eth_write -> eth.write
    ip.ipv4 -> ipv4.write
    ip.ipv6 -> ipv6.write
    icmp.ip_write -> ipv4.write
    udp.ip_write -> ip.write
    tcp.ip_write -> ip.write
    stack.netif -> net.write
    stack.ethernet -> eth.write
    stack.arpv4 -> arp.query
    stack.ipv4v6 -> ip.write
    stack.icmpv4 -> icmp.ip_write
    stack.udpv4v6 -> udp.ip_write
    stack.tcpv4v6 -> tcp.write
  }
}

@ HTTP server chain: Conduit TCP → TLS → CoHTTP.
@ The parent must wire [conduit_tcp.stack] to a stack.
topology HttpStack {
  instance conduit_tcp
  instance conduit
  instance http

  connections Connect {
    conduit.transport -> conduit_tcp.connect
    http.conduit -> conduit.connect
  }
}

@ Full website over vnetif (virtual ethernet).
topology StaticWebsite {
  import TcpipStack
  import HttpStack
  instance data
  instance certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
  }
}

@ Full website over Unix sockets.
topology UnixWebsite {
  instance socket_stack
  import HttpStack
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs

  connections Connect {
    conduit_tcp.stack -> socket_stack.provide
  }
}

@ MirageOS device catalogue and topologies.
@
@ Components mirror the MirageOS functor hierarchy.  Output ports
@ declare dependencies; the connection graph determines functor
@ application order and connect call arguments.
@
@ Three composition patterns are demonstrated:
@
@   {b Target switching.}  Each deployment target (Unix, Xen, Solo5)
@   is a different top-level topology sharing sub-topologies via
@   [import].  The caller picks which topology to instantiate.
@
@   {b Optional components.}  DNS is a sub-topology you import or
@   not.  No runtime flags — presence or absence of a capability
@   is a type-level fact.
@
@   {b Backend switching.}  Key-value stores come in several flavours
@   (crunch, tar-over-block, fat, in-memory).  Each is a different
@   component or a different [@ ocaml.module] binding.  The topology
@   picks one; the type system checks the wiring.

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

active component Backend {
  sync input port provide: Dep
}

@ ── Socket stack ────────────────────────────────────────

@ A pre-built OS socket stack for Unix targets.

active component SocketStack {
  sync input port provide: Dep
}

@ ── Network device ───────────────────────────────────────

active component Vnetif {
  output port backend: Dep
  sync input port write: NetWrite
}

@ ── Block device ────────────────────────────────────────
@
@ Leaf parameter for block storage.  The concrete module
@ depends on the target: [mirage-block-unix] for Unix,
@ [mirage-block-solo5] for Solo5, xenstore-backed for Xen.

active component Block {
  sync input port provide: Dep
}

@ ── Key-value stores ─────────────────────────────────────
@
@ The base [Kv] component defines the [Mirage_kv.RO] interface.
@ It is a leaf parameter — the topology binds it to a concrete
@ module via [@ ocaml.module] or leaves it as a functor argument.
@
@ For block-backed stores, separate components ([Tar_kv_ro],
@ [Fat_kv_ro]) take a [Block] dependency via their output port.

active component Kv {
  sync input port disconnect: Disconnect
  sync input port get: KvGet
  sync input port exists: KvExists
  sync input port list: KvList
  sync input port digest: KvDigest
}

@ Tar archive read-only KV over a block device.
@ [Tar_mirage.Make_KV_RO(Block)] then [connect block].
@ ocaml.functor Tar_mirage.Make_KV_RO
active component Tar_kv_ro {
  output port block: Dep
  sync input port provide: Dep
}

@ FAT filesystem read-only KV over a block device.
@ [Fat.KV_RO(Block)] then [connect block].
@ ocaml.functor Fat.KV_RO
active component Fat_kv_ro {
  output port block: Dep
  sync input port provide: Dep
}

@ ── Protocol stack ───────────────────────────────────────
@
@ Convention: when a component's name matches the OCaml module
@ (e.g. Arp -> Arp.Make, Static_ipv4 -> Static_ipv4.Make),
@ no [@ ocaml.functor] annotation is needed.

active component Ethernet {
  output port net_write: NetWrite
  sync input port write: EthWrite
}

active component Arp {
  output port eth_write: EthWrite
  sync input port query: ArpQuery
}

active component Static_ipv4 {
  output port eth_write: EthWrite
  output port arp_query: ArpQuery
  sync input port write: IpWrite
  sync input port cidr: IpConfig
}

active component Ipv6 {
  output port net_write: NetWrite
  output port eth_write: EthWrite
}

@ ocaml.functor Tcpip_stack_direct.IPV4V6
active component Ip {
  output port ipv4: IpWrite
  output port ipv6: IpWrite
  sync input port write: IpWrite
}

active component Icmpv4 {
  output port ip_write: IpWrite
}

active component Udp {
  output port ip_write: IpWrite
}

module Tcp {
  active component Flow {
    output port ip_write: IpWrite
    sync input port write: IpWrite
  }
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

module Cohttp_mirage {
  passive component Server {
    output port conduit: Dep
    sync input port listen: HttpConn
  }
}

@ ── DNS ─────────────────────────────────────────────────
@
@ Happy Eyeballs (RFC 8305) provides dual-stack connection
@ establishment.  The DNS client layers on top.  Both depend
@ on the TCP/IP stack; the parent topology wires them.

active component Happy_eyeballs_mirage {
  output port stack: Dep
  sync input port provide: Dep
}

active component Dns_client_mirage {
  output port stack: Dep
  output port happy_eyeballs: Dep
  sync input port resolve: Dep
}

@ ── Instances ────────────────────────────────────────────

@ Network
instance backend: Backend base id 0x050
instance net: Vnetif base id 0x100
instance socket_stack: SocketStack base id 0xD00

@ Protocol stack
instance eth: Ethernet base id 0x200
instance arp: Arp base id 0x300
instance ipv4: Static_ipv4 base id 0x400
instance ipv6: Ipv6 base id 0x450
instance ip: Ip base id 0x460
instance icmp: Icmpv4 base id 0x500
instance udp: Udp base id 0x600
instance tcp: Tcp.Flow base id 0x700
instance stack: TcpipStack base id 0xC00

@ Key-value stores (leaf parameters or bound modules)
instance data: Kv base id 0x800
instance certs: Kv base id 0x900

@ Key-value stores (block-backed)
instance data_block: Block base id 0x810
instance certs_block: Block base id 0x820
instance tar_data: Tar_kv_ro base id 0x830
instance tar_certs: Tar_kv_ro base id 0x840
instance fat_data: Fat_kv_ro base id 0x850
instance fat_certs: Fat_kv_ro base id 0x860

@ HTTP
instance conduit_tcp: Conduit_tcp base id 0xA00
instance conduit: Conduit base id 0xA10
instance http: Cohttp_mirage.Server base id 0xA20

@ DNS
instance happy_eyeballs: Happy_eyeballs_mirage base id 0xE00
instance dns_client: Dns_client_mirage base id 0xE10

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

@ ── DNS sub-topology ─────────────────────────────────────
@
@ Happy Eyeballs + DNS client.  The parent must wire both
@ [happy_eyeballs.stack] and [dns_client.stack] to a stack.
topology DnsStack {
  instance happy_eyeballs
  instance dns_client

  connections Connect {
    dns_client.happy_eyeballs -> happy_eyeballs.provide
  }
}

@ ── Target × feature matrix ─────────────────────────────
@
@ Each top-level topology is one deployment variant.
@ Sub-topologies are shared via [import]; the parent wires
@ any missing connections (which stack, which KV backend).

@ ── Vnetif topologies (Xen, Solo5, test) ────────────────
@
@ Crunch KV (build-time embedded), no DNS.
topology StaticWebsite {
  import TcpipStack
  import HttpStack
  instance data
  instance certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
  }
}

@ Crunch KV, with DNS.
topology StaticWebsiteWithDns {
  import TcpipStack
  import HttpStack
  import DnsStack
  instance data
  instance certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
    happy_eyeballs.stack -> stack.provide
    dns_client.stack -> stack.provide
  }
}

@ Tar-over-block KV, with DNS.
@ Each KV store reads from its own block device.
topology TarWebsite {
  import TcpipStack
  import HttpStack
  import DnsStack
  instance data_block
  instance certs_block
  instance tar_data
  instance tar_certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
    happy_eyeballs.stack -> stack.provide
    dns_client.stack -> stack.provide
    tar_data.block -> data_block.provide
    tar_certs.block -> certs_block.provide
  }
}

@ FAT-over-block KV, no DNS.
topology FatWebsite {
  import TcpipStack
  import HttpStack
  instance data_block
  instance certs_block
  instance fat_data
  instance fat_certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
    fat_data.block -> data_block.provide
    fat_certs.block -> certs_block.provide
  }
}

@ ── Unix topologies ─────────────────────────────────────
@
@ Unix socket stack, crunch KV bound to concrete modules.
topology UnixWebsite {
  @ ocaml.module Server.Unix_socket_stack
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

@ Unix socket stack, crunch KV, with DNS.
topology UnixWebsiteWithDns {
  @ ocaml.module Server.Unix_socket_stack
  instance socket_stack
  import HttpStack
  import DnsStack
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs

  connections Connect {
    conduit_tcp.stack -> socket_stack.provide
    happy_eyeballs.stack -> socket_stack.provide
    dns_client.stack -> socket_stack.provide
  }
}

@ Unix socket stack, in-memory KV (for testing).
topology UnixTestWebsite {
  @ ocaml.module Server.Unix_socket_stack
  instance socket_stack
  import HttpStack
  @ ocaml.module Mirage_kv_mem
  instance data
  @ ocaml.module Mirage_kv_mem
  instance certs

  connections Connect {
    conduit_tcp.stack -> socket_stack.provide
  }
}

@ MirageOS device catalogue.
@
@ Components mirror the MirageOS functor hierarchy.  Output ports
@ declare dependencies; the connection graph determines functor
@ application order and connect call arguments.

@ ── Network backend ──────────────────────────────────────

@ The leaf parameter for the virtual network switch.
@ For deployment, swap [Basic_backend.Make] with the
@ target backend (solo5, xen, unix tap).

active component Backend {
  sync input port write: NetWrite
  sync input port listen: NetListen
  sync input port mac: MacAddr
  sync input port mtu: Mtu
  sync input port disconnect: Disconnect
}

@ ── Socket stack ────────────────────────────────────────
@
@ Unix targets use OS sockets directly rather than the
@ direct protocol stack.  The composition is:
@   [Udpv4v6_socket] + [Tcpv4v6_socket] -> [Tcpip_stack_socket.V4V6]

active component Udpv4v6_socket {
  sync input port disconnect: Disconnect
}

active component Tcpv4v6_socket {
  sync input port disconnect: Disconnect
}

active component SocketStack {
  output port udp  output port tcp  sync input port disconnect: Disconnect
}

@ ── Network device ───────────────────────────────────────

active component Vnetif {
  output port backend  sync input port write: NetWrite
}

@ ── Block device ────────────────────────────────────────
@
@ Leaf parameter for block storage.  The concrete module
@ depends on the target: [mirage-block-unix] for Unix,
@ [mirage-block-solo5] for Solo5, xenstore-backed for Xen.

active component Block {
  type Error
  type WriteError
  sync input port disconnect: Disconnect
  sync input port get_info: BlockGetInfo
  sync input port read: BlockRead
  sync input port write: BlockWrite
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
  type Error
  type Key
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
  output port block  sync input port disconnect: Disconnect
}

@ FAT filesystem read-only KV over a block device.
@ [Fat.KV_RO(Block)] then [connect block].
@ ocaml.functor Fat.KV_RO
active component Fat_kv_ro {
  output port block  sync input port disconnect: Disconnect
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
  sync input port cidr: IpCidr
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
  sync input port ipv4_only: IpOnly
  sync input port ipv6_only: IpOnly
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
  sync input port disconnect: Disconnect  output port netif  output port ethernet  output port arpv4  output port ipv4v6  output port icmpv4  output port udpv4v6  output port tcpv4v6
}

@ ── Application ────────────────────────────────────────
@
@ The user-facing HTTPS server functor.  Takes KV stores for
@ static data and TLS certificates, plus the TCP/IP stack.
@ The conduit and CoHTTP modules are created internally.
@ [Server.HTTPS(Data)(Certs)(Stack).start data certs stack].

@ ocaml.functor Server.HTTPS
active component Server {
  output port data  output port certs  output port stack}

@ ── DNS ─────────────────────────────────────────────────
@
@ Happy Eyeballs (RFC 8305) provides dual-stack connection
@ establishment.  The DNS client layers on top.  Both depend
@ on the TCP/IP stack; the parent topology wires them.

active component Happy_eyeballs_mirage {
  output port stack  sync input port disconnect: Disconnect
}

active component Dns_client_mirage {
  output port stack  output port happy_eyeballs  sync input port resolve}

@ ── Instances ────────────────────────────────────────────

@ Network
instance backend: Backend base id 0x050
instance net: Vnetif base id 0x100
instance udp_socket: Udpv4v6_socket base id 0xD00
instance tcp_socket: Tcpv4v6_socket base id 0xD10
instance socket_stack: SocketStack base id 0xD20

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

@ Application
instance server: Server base id 0xA30

@ DNS
instance happy_eyeballs: Happy_eyeballs_mirage base id 0xE00
instance dns_client: Dns_client_mirage base id 0xE10

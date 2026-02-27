@ MirageOS device catalogue.
@
@ Components model device constructors. Output ports declare
@ dependencies; [sync input port connect] is the universal
@ constructor-result port used as connection target.

@ ── Leaf devices (no dependencies) ──────────────────────

active component Backend { sync input port connect }
active component Udpv4v6_socket { sync input port connect }
active component Tcpv4v6_socket { sync input port connect }
active component Block { sync input port connect }
active component Kv { sync input port connect }

@ ── Socket stack ────────────────────────────────────────

active component SocketStack {
  sync input port connect
  output port udp
  output port tcp
}

@ ── Network device ──────────────────────────────────────

active component Vnetif {
  sync input port connect
  output port backend
}

@ ── Block-backed KV stores ──────────────────────────────

@ ocaml.functor Tar_mirage.Make_KV_RO
active component Tar_kv_ro {
  sync input port connect
  output port block
}

@ ocaml.functor Fat.KV_RO
active component Fat_kv_ro {
  sync input port connect
  output port block
}

@ ── Protocol stack ──────────────────────────────────────

active component Ethernet {
  sync input port connect
  output port net
}

active component Arp {
  sync input port connect
  output port eth
}

active component Static_ipv4 {
  sync input port connect
  output port eth
  output port arp
}

active component Ipv6 {
  sync input port connect
  output port net
  output port eth
}

@ ocaml.functor Tcpip_stack_direct.IPV4V6
active component Ip {
  sync input port connect
  output port ipv4
  output port ipv6
}

active component Icmpv4 {
  sync input port connect
  output port ip
}

active component Udp {
  sync input port connect
  output port ip
}

module Tcp {
  active component Flow {
    sync input port connect
    output port ip
  }
}

@ ocaml.functor Tcpip_stack_direct.MakeV4V6
active component TcpipStack {
  sync input port connect
  output port netif
  output port ethernet
  output port arpv4
  output port ipv4v6
  output port icmpv4
  output port udpv4v6
  output port tcpv4v6
}

@ ── Application ─────────────────────────────────────────

@ ocaml.functor Server.HTTPS
active component Server {
  sync input port connect
  output port data
  output port certs
  output port stack
}

@ ── DNS ─────────────────────────────────────────────────

active component Happy_eyeballs_mirage {
  sync input port connect
  output port stack
}

active component Dns_client_mirage {
  sync input port connect
  output port stack
  output port happy_eyeballs
}

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

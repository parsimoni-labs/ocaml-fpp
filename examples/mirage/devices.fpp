@ MirageOS module type and instance catalogue.
@
@ Components model module constructors (functors). Output ports declare
@ dependencies; [sync input port connect] is the universal
@ constructor-result port used as connection target.

@ ── Leaf devices (no dependencies) ──────────────────────

@ ocaml.sig Vnetif.BACKEND
passive component Backend { sync input port connect }
passive component Udpv4v6_socket {
  param ipv4Only: bool default false
  param ipv6Only: bool default false
  @ ocaml.positional
  param ipv4Cidr: string
  @ ocaml.positional
  param ipv6Cidr: string
  sync input port connect
}
passive component Tcpv4v6_socket {
  param ipv4Only: bool default false
  param ipv6Only: bool default false
  @ ocaml.positional
  param ipv4Cidr: string
  @ ocaml.positional
  param ipv6Cidr: string
  sync input port connect
}
@ ocaml.sig Mirage_block.S
passive component Block {
  param name: string default "disk"
  sync input port connect
}
@ ocaml.sig Mirage_kv.RO
passive component Kv { sync input port connect }

@ ── Runtime config ────────────────────────────────────────
@
@ A component named [Runtime] is a runtime config provider.
@ Its output ports model labeled keyword arguments injected
@ into the connect call of target instances.
@
@ Each sub-topology defines its own [Runtime] component inside
@ an FPP module, so config is scoped to where it is used.
@ See [stacks.fpp] for the concrete definitions.

@ ── Netif (Unix network interface) ──────────────────────

passive component Netif {
  @ ocaml.positional
  param device: string default "tap0"
  sync input port connect
}

@ ── Socket stack ────────────────────────────────────────

@ ocaml.nofunctor
passive component Stackv4v6 {
  sync input port connect
  output port udp
  output port tcp
}

@ ── Network module ───────────────────────────────────────

passive component Vnetif {
  sync input port connect
  output port backend
}

@ ── Block-backed KV stores ──────────────────────────────

@ ocaml.module Tar_mirage.Make_KV_RO
passive component Tar_kv_ro {
  sync input port connect
  output port block
}

@ ocaml.module Fat.KV_RO
passive component Fat_kv_ro {
  sync input port connect
  output port block
}

@ ── Protocol stack ──────────────────────────────────────

passive component Ethernet {
  sync input port connect
  output port net
}

passive component Arp {
  sync input port connect
  output port eth
}

passive component Static_ipv4 {
  sync input port connect
  output port eth
  output port arp
}

passive component Ipv6 {
  sync input port connect
  output port net
  output port eth
}

@ ocaml.module Tcpip_stack_direct.IPV4V6
passive component Ip {
  sync input port connect
  output port ipv4
  output port ipv6
}

passive component Icmpv4 {
  sync input port connect
  output port ip
}

passive component Udp {
  sync input port connect
  output port ip
}

module Tcp {
  passive component Flow {
    sync input port connect
    output port ip
  }
}

@ ocaml.module Tcpip_stack_direct.MakeV4V6
passive component DirectStackv4v6 {
  sync input port connect
  output port netif
  output port ethernet
  output port arpv4
  output port ipv4v6
  output port icmpv4
  output port udpv4v6
  output port tcpv4v6
}

@ ── Conduit / TLS / CoHTTP ─────────────────────────────
@
@ Each layer wraps the previous one. In the generated code,
@ the connect functions are pass-throughs ([Lwt.return x]).

passive component ConduitTcp {
  sync input port start
  output port stack
}

@ ocaml.module Conduit_mirage.TLS
passive component ConduitTls {
  sync input port connect
  output port conduit
}

module Cohttp_mirage {
  module Server {
    @ ocaml.module Cohttp_mirage.Server.Make
    passive component Make {
      sync input port connect
      output port conduit
    }
  }
}

@ ── Application ─────────────────────────────────────────
@
@ Dispatch takes KV stores and a network stack.
@ [Server.Make_dispatch] wraps [Server.HTTPS] with the
@ conduit / TLS / CoHTTP chain built from the stack.

@ ocaml.module Server.Make_dispatch
passive component Dispatch {
  sync input port connect
  output port data
  output port certs
  output port stack
}

@ ── DNS ─────────────────────────────────────────────────

passive component Happy_eyeballs_mirage {
  sync input port connect
  output port stack
}

passive component Dns_client_mirage {
  sync input port start
  output port stack
  output port happy_eyeballs
}

@ ── Instances ────────────────────────────────────────────

@ Network
instance backend: Backend base id 0x050
instance net: Vnetif base id 0x100
instance udpv4v6_socket: Udpv4v6_socket base id 0xD00
instance tcpv4v6_socket: Tcpv4v6_socket base id 0xD10
instance stackv4v6: Stackv4v6 base id 0xD20

@ Protocol stack
instance ethernet: Ethernet base id 0x200
instance arp: Arp base id 0x300
instance ipv4: Static_ipv4 base id 0x400
instance ipv6: Ipv6 base id 0x450
instance ip: Ip base id 0x460
instance icmp: Icmpv4 base id 0x500
instance udp: Udp base id 0x600
instance tcp: Tcp.Flow base id 0x700
instance stack: DirectStackv4v6 base id 0xC00

@ Key-value stores (leaf parameters or bound modules)
instance data: Kv base id 0x800
instance certs: Kv base id 0x900
instance htdocs_data: Kv base id 0x870
instance tls_data: Kv base id 0x880

@ Key-value stores (block-backed)
instance data_block: Block base id 0x810
instance certs_block: Block base id 0x820
instance tar_data: Tar_kv_ro base id 0x830
instance tar_certs: Tar_kv_ro base id 0x840
instance fat_data: Fat_kv_ro base id 0x850
instance fat_certs: Fat_kv_ro base id 0x860

@ Application
instance dispatch: Dispatch base id 0xA30

@ DNS
instance happy_eyeballs_mirage: Happy_eyeballs_mirage base id 0xE00
instance dns_client: Dns_client_mirage base id 0xE10

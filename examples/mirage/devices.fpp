@ MirageOS device catalogue.
@
@ Components model device constructors. Output ports declare
@ dependencies; [async input port connect] is the universal
@ constructor-result port used as connection target.

@ ── Leaf devices (no dependencies) ──────────────────────

@ ocaml.sig Vnetif.BACKEND
active component Backend { async input port connect }
active component Udpv4v6_socket { async input port connect }
active component Tcpv4v6_socket { async input port connect }
@ ocaml.sig Mirage_block.S
active component Block { async input port connect }
@ ocaml.sig Mirage_kv.RO
active component Kv { async input port connect }

@ ── Runtime config ────────────────────────────────────────
@
@ A component named [Runtime] is a runtime config provider.
@ Its output ports model labeled keyword arguments injected
@ into the connect call of target instances.
@
@ Each sub-topology defines its own [Runtime] component inside
@ an FPP module, so config is scoped to where it is used.
@ See [stacks.fpp] for the concrete definitions.

@ ── Socket stack ────────────────────────────────────────

active component Stackv4v6 {
  async input port connect
  output port udp
  output port tcp
}

@ ── Network device ──────────────────────────────────────

active component Vnetif {
  async input port connect
  output port backend
}

@ ── Block-backed KV stores ──────────────────────────────

@ ocaml.functor Tar_mirage.Make_KV_RO
active component Tar_kv_ro {
  async input port connect
  output port block
}

@ ocaml.functor Fat.KV_RO
active component Fat_kv_ro {
  async input port connect
  output port block
}

@ ── Protocol stack ──────────────────────────────────────

active component Ethernet {
  async input port connect
  output port net
}

active component Arp {
  async input port connect
  output port eth
}

active component Static_ipv4 {
  async input port connect
  output port eth
  output port arp
}

active component Ipv6 {
  async input port connect
  output port net
  output port eth
}

@ ocaml.functor Tcpip_stack_direct.IPV4V6
active component Ip {
  async input port connect
  output port ipv4
  output port ipv6
}

active component Icmpv4 {
  async input port connect
  output port ip
}

active component Udp {
  async input port connect
  output port ip
}

module Tcp {
  active component Flow {
    async input port connect
    output port ip
  }
}

@ ocaml.functor Tcpip_stack_direct.MakeV4V6
active component DirectStackv4v6 {
  async input port connect
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

@ ocaml.functor Conduit_mirage.TCP
active component ConduitTcp {
  async input port connect
  output port stack
}

@ ocaml.functor Conduit_mirage.TLS
active component ConduitTls {
  async input port connect
  output port conduit
}

module Cohttp_mirage {
  module Server {
    @ ocaml.functor Cohttp_mirage.Server.Make
    active component Make {
      async input port connect
      output port conduit
    }
  }
}

@ ── Application ─────────────────────────────────────────
@
@ Dispatch takes KV stores and a network stack.
@ Conduit / TLS / CoHTTP layers are created internally
@ by the [Server.HTTPS] functor.

@ ocaml.functor Server.HTTPS
active component Dispatch {
  async input port connect
  output port data
  output port certs
  output port stack
}

@ ── DNS ─────────────────────────────────────────────────

active component Happy_eyeballs_mirage {
  async input port connect
  output port stack
}

active component Dns_client_mirage {
  async input port connect
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
instance eth: Ethernet base id 0x200
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
instance happy_eyeballs: Happy_eyeballs_mirage base id 0xE00
instance dns_client: Dns_client_mirage base id 0xE10

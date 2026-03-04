@ MirageOS infrastructure sub-topologies.
@
@ Reusable building blocks composed via [import] by
@ deployment topologies.  Each sub-topology wires a
@ layer of the stack; the parent provides missing
@ connections (e.g. which network backend to use).
@
@ [TcpipStack] and [DnsStack] define their own [Runtime]
@ component inside a module, scoping config to where it is
@ used.  [SocketStack] uses [@ ocaml.param] bindings instead.

@ ── Runtime components ────────────────────────────────

@ Runtime config for TCP/IP stack topologies.
module Tcpip {
  passive component Runtime {
    output port ipv4_only: [2]
    output port ipv6_only: [2]
    @ IPv4 config (required)
    output port cidr
    @ ocaml.optional
    output port gateway
  }
}

@ Runtime config for DNS topologies.
module Dns {
  passive component Runtime {
    @ Happy Eyeballs tuning (optional)
    @ ocaml.optional
    output port aaaa_timeout
    @ ocaml.optional
    output port connect_delay
    @ ocaml.optional
    output port connect_timeout
    @ ocaml.optional
    output port resolve_timeout
    @ ocaml.optional
    output port resolve_retries
    @ ocaml.optional
    output port timer_interval

    @ DNS client config (optional)
    @ ocaml.optional
    output port nameservers
    @ ocaml.optional
    output port timeout
    @ ocaml.optional
    output port cache_size
  }
}

@ ── Runtime instances ─────────────────────────────────

instance tcpip_runtime: Tcpip.Runtime base id 0xB01
instance dns_runtime: Dns.Runtime base id 0xB03

@ ── Sub-topologies ────────────────────────────────────

@ Protocol stack: backend through [MakeV4V6].
@ The [tcpip_runtime] instance provides [~cidr], [?gateway],
@ [~ipv4_only] and [~ipv6_only] as keyword arguments.
topology TcpipStack {
  instance tcpip_runtime
  instance backend
  instance net
  instance ethernet
  instance arp
  instance ipv4
  instance ipv6
  instance ip
  instance icmp
  instance udp
  instance tcp
  instance stack

  connections Connect {
    tcpip_runtime.cidr -> ipv4.connect
    tcpip_runtime.gateway -> ipv4.connect
    tcpip_runtime.ipv4_only -> ip.connect
    tcpip_runtime.ipv6_only -> ip.connect
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

@ Unix socket stack: Udpv4v6_socket + Tcpv4v6_socket → V4V6.
@ The composition is value-level: [V4V6.connect udp tcp], not
@ a functor application.  Default param bindings are set here;
@ parent topologies can override by re-declaring the instance.
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

@ Happy Eyeballs + DNS client.  The parent must wire
@ [happy_eyeballs_mirage.stack] and [dns_client.stack] to a stack.
@ Happy Eyeballs uses [connect_device] for initialisation.
@ Runtime kwargs (HE tuning, DNS config) are wired by the
@ parent topology via a [Dns.Runtime] instance.
topology DnsStack {
  instance happy_eyeballs_mirage
  instance dns_client

  connections Start {
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect
  }
}

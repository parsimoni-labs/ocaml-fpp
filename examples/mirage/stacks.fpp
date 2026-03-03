@ MirageOS infrastructure sub-topologies.
@
@ Reusable building blocks composed via [import] by
@ deployment topologies.  Each sub-topology wires a
@ layer of the stack; the parent provides missing
@ connections (e.g. which network backend to use).
@
@ Each sub-topology defines its own [Runtime] component
@ inside a module, scoping config to where it is used.

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

@ Runtime config for Unix socket stack topologies.
module Socket {
  passive component Runtime {
    output port ipv4_only: [2]
    output port ipv6_only: [2]
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
instance socket_runtime: Socket.Runtime base id 0xB02
instance dns_runtime: Dns.Runtime base id 0xB03

@ ── Sub-topologies ────────────────────────────────────

@ Protocol stack: backend through [MakeV4V6].
@ The [tcpip_runtime] instance provides [~cidr], [?gateway],
@ [~ipv4_only] and [~ipv6_only] as keyword arguments.
topology TcpipStack {
  instance tcpip_runtime
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
    tcpip_runtime.cidr -> ipv4.connect
    tcpip_runtime.gateway -> ipv4.connect
    tcpip_runtime.ipv4_only -> ip.connect
    tcpip_runtime.ipv6_only -> ip.connect
    net.backend -> backend.connect
    eth.net -> net.connect
    arp.eth -> eth.connect
    ipv4.eth -> eth.connect
    ipv4.arp -> arp.connect
    ipv6.net -> net.connect
    ipv6.eth -> eth.connect
    ip.ipv4 -> ipv4.connect
    ip.ipv6 -> ipv6.connect
    icmp.ip -> ipv4.connect
    udp.ip -> ip.connect
    tcp.ip -> ip.connect
    stack.netif -> net.connect
    stack.ethernet -> eth.connect
    stack.arpv4 -> arp.connect
    stack.ipv4v6 -> ip.connect
    stack.icmpv4 -> icmp.connect
    stack.udpv4v6 -> udp.connect
    stack.tcpv4v6 -> tcp.connect
  }
}

@ Unix socket stack: Udpv4v6_socket + Tcpv4v6_socket → V4V6.
@ The composition is value-level: [V4V6.connect udp tcp], not
@ a functor application.  Parent topologies bind the socket
@ instances to wrapper modules via [@ ocaml.module] (the real
@ connect signatures differ from the generated convention).
@
@ The [socket_runtime] instance provides [~ipv4_only] and
@ [~ipv6_only] as keyword arguments to the socket connect calls.
topology SocketStack {
  instance socket_runtime
  instance udpv4v6_socket
  instance tcpv4v6_socket
  instance stackv4v6

  connections Connect {
    socket_runtime.ipv4_only -> udpv4v6_socket.connect
    socket_runtime.ipv6_only -> udpv4v6_socket.connect
    socket_runtime.ipv4_only -> tcpv4v6_socket.connect
    socket_runtime.ipv6_only -> tcpv4v6_socket.connect
    stackv4v6.udp -> udpv4v6_socket.connect
    stackv4v6.tcp -> tcpv4v6_socket.connect
  }
}

@ Happy Eyeballs + DNS client.  The parent must wire
@ [happy_eyeballs.stack] and [dns_client.stack] to a stack.
@ Happy Eyeballs uses [connect_device] for initialisation.
@ Runtime kwargs (HE tuning, DNS config) are wired by the
@ parent topology via a [Dns.Runtime] instance.
topology DnsStack {
  instance happy_eyeballs
  instance dns_client

  connections Connect {
    dns_client.happy_eyeballs -> happy_eyeballs.connect
  }
}

@ MirageOS infrastructure sub-topologies.
@
@ Reusable building blocks composed via [import] by
@ deployment topologies.  Each sub-topology wires a
@ layer of the stack; the parent provides missing
@ connections (e.g. which network backend to use).

@ ── Sub-topologies ────────────────────────────────────

@ Protocol stack: backend through [MakeV4V6].
@ IPv4 and IP config is passed via [@ ocaml.param] bindings.
topology TcpipStack {
  instance backend
  @ ocaml.module Vnetif.Make
  instance net
  instance ethernet
  instance arp
  @ ocaml.param cidr (Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24")
  @ ocaml.module Static_ipv4.Make
  instance ipv4
  instance ipv6
  @ ocaml.param ipv4_only false
  @ ocaml.param ipv6_only false
  instance ip
  @ ocaml.module Icmpv4.Make
  instance icmp
  instance udp
  @ ocaml.module Tcp.Flow.Make
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
topology DnsStack {
  instance happy_eyeballs_mirage
  instance dns_client

  connections Start {
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect
  }
}

@ MirageOS infrastructure sub-topologies.
@
@ Reusable building blocks composed via [import] by
@ deployment topologies.  Each sub-topology wires a
@ layer of the stack; the parent provides missing
@ connections (e.g. which network backend to use).

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

@ Unix socket stack: Udpv4v6_socket + Tcpv4v6_socket → V4V6.
@ The composition is value-level: [V4V6.connect udp tcp], not
@ a functor application.  Parent topologies bind the three
@ instances to concrete (wrapper) modules via [@ ocaml.module].
topology SocketStack {
  instance udp_socket
  instance tcp_socket
  instance socket_stack

  connections Connect {
    socket_stack.udp -> udp_socket.provide
    socket_stack.tcp -> tcp_socket.provide
  }
}

@ Happy Eyeballs + DNS client.  The parent must wire both
@ [happy_eyeballs.stack] and [dns_client.stack] to a stack.
topology DnsStack {
  instance happy_eyeballs
  instance dns_client

  connections Connect {
    dns_client.happy_eyeballs -> happy_eyeballs.provide
  }
}

@ MirageOS application components and deployment topologies.
@
@ Components model application entry points. [sync input port start]
@ declares the start function; output ports declare module
@ dependencies. Flat topologies bind all instances and generate
@ [main.ml] with [Mirage_runtime] entry points.

@ ── Application component shapes ────────────────────────────

@ Standalone application (no module dependencies).
passive component StandaloneApp { sync input port start }

@ Block application.
passive component BlockApp {
  sync input port start
  output port block
}

@ KV-RO application.
passive component KvRoApp {
  sync input port start
  output port kv
}

@ Network stack application.
passive component StackApp {
  sync input port start
  output port stack
}

@ DNS client application.
@ ocaml.sig Dns_client_mirage.S
passive component DnsClientApp {
  sync input port start
  output port dns
}

@ Raw network application (e.g. DHCP server).
@ ocaml.sig Mirage_net.S
passive component NetApp {
  sync input port start
  output port net
}

@ IPv6 ping application (raw network + ethernet + IPv6).
passive component Ping6App {
  sync input port start
  output port net
  output port eth
  output port ipv6
}

@ Conduit server application.
@ ocaml.sig Conduit_mirage.S
passive component ConduitApp {
  sync input port start
  output port conduit
}

@ ── Application instances ─────────────────────────────────

instance app: StandaloneApp base id 0x5000
instance block_app: BlockApp base id 0x5100
instance kv_app: KvRoApp base id 0x5200
instance stack_app: StackApp base id 0x5300
instance dns_client_app: DnsClientApp base id 0x5400
instance net_app: NetApp base id 0x5500
instance ping6_app: Ping6App base id 0x5600
instance conduit_app: ConduitApp base id 0x5700

@ ── Extra instances ──────────────────────────────────────

instance ramdisk: Block base id 0x6000
instance kv_store: Kv base id 0x6100
instance conduit_tcp: ConduitTcp base id 0x6200
instance netif: Backend base id 0x6300

@ ── Standalone topologies ─────────────────────────────────

topology UnixHello {
  @ ocaml.module Unikernel
  instance app
}

topology UnixHelloKey {
  @ ocaml.module Unikernel
  instance app
}

topology UnixClock {
  @ ocaml.module Unikernel
  instance app
}

topology UnixCrypto {
  @ ocaml.module Unikernel
  instance app
}

topology UnixHeads1 {
  @ ocaml.module Unikernel
  instance app
}

topology UnixHeads2 {
  @ ocaml.module Unikernel
  instance app
}

topology UnixTimeout1 {
  @ ocaml.module Unikernel
  instance app
}

topology UnixTimeout2 {
  @ ocaml.module Unikernel
  instance app
}

topology UnixEchoServer {
  @ ocaml.module Unikernel
  instance app
}

@ ── Block topologies ──────────────────────────────────────

topology UnixBlock {
  @ ocaml.param name "block-test"
  @ ocaml.module Ramdisk
  instance ramdisk
  @ ocaml.module Unikernel.Main
  instance block_app

  connections Start {
    block_app.block -> ramdisk.connect
  }
}

topology UnixDiskLottery {
  @ ocaml.param name "lottery-disk"
  @ ocaml.module Ramdisk
  instance ramdisk
  @ ocaml.module Unikernel.Main
  instance block_app

  connections Start {
    block_app.block -> ramdisk.connect
  }
}

@ ── KV topology ───────────────────────────────────────────

topology UnixKvRo {
  @ ocaml.module Static_t
  instance kv_store
  @ ocaml.module Unikernel.Main
  instance kv_app

  connections Start {
    kv_app.kv -> kv_store.connect
  }
}

@ ── Socket stack topologies ───────────────────────────────

topology UnixNetwork {
  import SocketStack
  @ ocaml.module Udpv4v6_socket
  instance udpv4v6_socket
  @ ocaml.module Tcpv4v6_socket
  instance tcpv4v6_socket
  @ ocaml.module Tcpip_stack_socket.V4V6
  instance stackv4v6
  @ ocaml.module Unikernel.Main
  instance stack_app

  connections Start {
    stack_app.stack -> stackv4v6.connect
  }
}

topology UnixConduit {
  import SocketStack
  @ ocaml.module Udpv4v6_socket
  instance udpv4v6_socket
  @ ocaml.module Tcpv4v6_socket
  instance tcpv4v6_socket
  @ ocaml.module Tcpip_stack_socket.V4V6
  instance stackv4v6
  instance conduit_tcp
  @ ocaml.module Unikernel.Main
  instance conduit_app

  connections Connect {
    conduit_tcp.stack -> stackv4v6.connect
  }

  connections Start {
    conduit_app.conduit -> conduit_tcp.connect
  }
}

@ ── Socket stack + DNS topology ───────────────────────────

topology UnixDns {
  import SocketStack
  @ ocaml.module Udpv4v6_socket
  instance udpv4v6_socket
  @ ocaml.module Tcpv4v6_socket
  instance tcpv4v6_socket
  @ ocaml.module Tcpip_stack_socket.V4V6
  instance stackv4v6
  import DnsStack
  instance dns_runtime
  @ ocaml.module Unikernel.Make
  instance dns_client_app

  connections Connect_device {
    dns_runtime.aaaa_timeout -> happy_eyeballs.connect
    dns_runtime.connect_delay -> happy_eyeballs.connect
    dns_runtime.connect_timeout -> happy_eyeballs.connect
    dns_runtime.resolve_timeout -> happy_eyeballs.connect
    dns_runtime.resolve_retries -> happy_eyeballs.connect
    dns_runtime.timer_interval -> happy_eyeballs.connect
    happy_eyeballs.stack -> stackv4v6.connect
  }

  connections Connect {
    dns_runtime.nameservers -> dns_client.connect
    dns_runtime.timeout -> dns_client.connect
    dns_runtime.cache_size -> dns_client.connect
    dns_client.stack -> stackv4v6.connect
  }

  connections Start {
    dns_client_app.dns -> dns_client.connect
  }
}

@ ── Netif topologies ──────────────────────────────────────

topology UnixDhcp {
  @ ocaml.module Netif
  instance netif
  @ ocaml.module Unikernel.Main
  instance net_app

  connections Start {
    net_app.net -> netif.connect
  }
}

topology UnixPing6 {
  @ ocaml.module Netif
  instance netif
  instance eth
  instance ipv6
  @ ocaml.module Unikernel.Main
  instance ping6_app

  connections Connect {
    eth.net -> netif.connect
    ipv6.net -> netif.connect
    ipv6.eth -> eth.connect
  }

  connections Start {
    ping6_app.net -> netif.connect
    ping6_app.eth -> eth.connect
    ping6_app.ipv6 -> ipv6.connect
  }
}

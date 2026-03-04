@ MirageOS application components and deployment topologies.
@
@ Components model application entry points. [sync input port start]
@ declares the start function; output ports declare module
@ dependencies. Topologies bind all instances and generate
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

instance unikernel: StandaloneApp base id 0x5000
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
instance netif: Netif base id 0x6300

@ ── Standalone topologies ─────────────────────────────────

topology UnixHello {
  instance unikernel
}

topology UnixHelloKey {
  instance unikernel
}

topology UnixClock {
  instance unikernel
}

topology UnixCrypto {
  instance unikernel
}

topology UnixHeads1 {
  instance unikernel
}

topology UnixHeads2 {
  instance unikernel
}

topology UnixTimeout1 {
  instance unikernel
}

topology UnixTimeout2 {
  instance unikernel
}

topology UnixEchoServer {
  instance unikernel
}

@ ── Block topologies ──────────────────────────────────────

topology UnixBlock {
  @ ocaml.param name "block-test"
  instance ramdisk
  @ ocaml.module Unikernel.Main
  instance block_app

  connections Start {
    block_app.block -> ramdisk.connect
  }
}

topology UnixDiskLottery {
  @ ocaml.param name "lottery-disk"
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
  instance stackv4v6
  @ ocaml.module Unikernel.Main
  instance stack_app

  connections Start {
    stack_app.stack -> stackv4v6.connect
  }
}

topology UnixConduit {
  import SocketStack
  instance stackv4v6
  instance conduit_tcp
  @ ocaml.module Unikernel.Main
  instance conduit_app

  connections Start {
    conduit_tcp.stack -> stackv4v6.connect
    conduit_app.conduit -> conduit_tcp.start
  }
}

@ ── Socket stack + DNS topology ───────────────────────────

topology UnixDns {
  import SocketStack
  instance stackv4v6
  instance happy_eyeballs_mirage
  instance dns_client
  @ ocaml.module Unikernel.Make
  instance dns_client_app

  connections Connect_device {
    happy_eyeballs_mirage.stack -> stackv4v6.connect
  }

  connections Start {
    dns_client.stack -> stackv4v6.connect
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
    dns_client_app.dns -> dns_client.start
  }
}

@ ── Netif topologies ──────────────────────────────────────

topology UnixDhcp {
  instance netif
  @ ocaml.module Unikernel.Main
  instance net_app

  connections Start {
    net_app.net -> netif.connect
  }
}

topology UnixPing6 {
  instance netif
  instance ethernet
  instance ipv6
  @ ocaml.module Unikernel.Main
  instance ping6_app

  connections Connect {
    ethernet.net -> netif.connect
    ipv6.net -> netif.connect
    ipv6.eth -> ethernet.connect
  }

  connections Start {
    ping6_app.net -> netif.connect
    ping6_app.eth -> ethernet.connect
    ping6_app.ipv6 -> ipv6.connect
  }
}

@ ── Direct network topology ─────────────────────────────

topology DirectNetwork {
  import TcpipStack
  @ ocaml.module Backend
  instance backend
  @ ocaml.module Unikernel.Main
  instance stack_app

  connections Start {
    stack_app.stack -> stack.connect
  }
}

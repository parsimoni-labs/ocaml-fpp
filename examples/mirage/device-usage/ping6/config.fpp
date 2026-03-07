passive component App {
  sync input port start: serial
  output port net: serial
  output port eth: serial
  output port ipv6: serial
}

instance app: App base id 0

topology UnixPing6 {
  instance netif(_0 = "tap0")
  instance ethernet
  instance ipv6
  @ ocaml.module Unikernel.Main
  instance app

  connections Connect {
    ethernet.net -> netif.connect
    ipv6.net -> netif.connect
    ipv6.eth -> ethernet.connect
  }

  connections Start {
    app.net -> netif.connect
    app.eth -> ethernet.connect
    app.ipv6 -> ipv6.connect
  }
}

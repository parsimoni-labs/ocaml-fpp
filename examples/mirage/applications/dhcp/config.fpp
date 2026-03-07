passive component App {
  sync input port start: serial
  output port net: serial
}

instance netif: Netif base id 0
instance app: App base id 0

topology UnixDhcp {
  instance netif(_0 = "tap0")
  @ ocaml.module Unikernel.Main
  instance app

  connections Start {
    app.net -> netif.connect
  }
}

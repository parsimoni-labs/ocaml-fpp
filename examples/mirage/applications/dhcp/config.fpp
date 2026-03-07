module Unikernel {
  passive component Main {
    sync input port start: serial
    output port net: serial
  }
}

instance app: Unikernel.Main base id 0

topology UnixDhcp {
  instance netif(_0 = "tap0")
  instance app

  connections Start {
    app.net -> netif.connect
  }
}

module Unikernel {
  passive component Main {
    sync input port start: serial
    output port net: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixDhcp {
  instance netif(_0 = "tap0")
  instance unikernel

  connections Start {
    unikernel.net -> netif.connect
  }
}

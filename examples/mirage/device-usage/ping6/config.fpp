module Unikernel {
  passive component Main {
    async input port start: serial
    output port net: serial
    output port eth: serial
    output port ipv6: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixPing6 {
  instance backend
  instance net
  instance ethernet
  instance ipv6
  instance unikernel

  connections Connect {
    net.backend -> backend.connect
    ethernet.net -> net.connect
    ipv6.net -> net.connect
    ipv6.eth -> ethernet.connect
  }

  connections Start {
    unikernel.net -> net.connect
    unikernel.eth -> ethernet.connect
    unikernel.ipv6 -> ipv6.connect
  }
}

topology Solo5Ping6 {
  instance netif(_0 = "service")
  instance ethernet
  instance ipv6
  instance unikernel

  connections Connect {
    ethernet.net -> netif.connect
    ipv6.net -> netif.connect
    ipv6.eth -> ethernet.connect
  }

  connections Start {
    unikernel.net -> netif.connect
    unikernel.eth -> ethernet.connect
    unikernel.ipv6 -> ipv6.connect
  }
}

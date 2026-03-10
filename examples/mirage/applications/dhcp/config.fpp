module Unikernel {
  passive component Main {
    async input port start: serial
    output port net: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixDhcp {
  instance backend
  instance net
  instance unikernel

  connections Connect {
    net.backend -> backend.connect
  }

  connections Start {
    unikernel.net -> net.connect
  }
}

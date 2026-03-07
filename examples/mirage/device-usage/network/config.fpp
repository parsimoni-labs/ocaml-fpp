module Unikernel {
  passive component Main {
    sync input port start: serial
    output port stack: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixNetwork {
  import SocketStack
  instance stackv4v6
  instance unikernel

  connections Start {
    unikernel.stack -> stackv4v6.connect
  }
}

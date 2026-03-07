module Unikernel {
  passive component Main {
    sync input port start: serial
    output port conduit: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixConduit {
  import SocketStack
  instance stackv4v6
  instance conduit_tcp
  instance unikernel

  connections Start {
    conduit_tcp.stack -> stackv4v6.connect
    unikernel.conduit -> conduit_tcp.start
  }
}

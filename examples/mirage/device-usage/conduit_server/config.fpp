module Unikernel {
  passive component Main {
    sync input port start: serial
    output port conduit: serial
  }
}

instance app: Unikernel.Main base id 0

topology UnixConduit {
  import SocketStack
  instance stackv4v6
  instance conduit_tcp
  instance app

  connections Start {
    conduit_tcp.stack -> stackv4v6.connect
    app.conduit -> conduit_tcp.start
  }
}

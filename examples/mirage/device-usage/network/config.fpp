module Unikernel {
  passive component Main {
    sync input port start: serial
    output port stack: serial
  }
}

instance app: Unikernel.Main base id 0

topology UnixNetwork {
  import SocketStack
  instance stackv4v6
  instance app

  connections Start {
    app.stack -> stackv4v6.connect
  }
}

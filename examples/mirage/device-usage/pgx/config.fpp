module Unikernel {
  passive component Make {
    sync input port start: serial
    output port stack: serial
  }
}

instance unikernel: Unikernel.Make base id 0

topology UnixPgx {
  import SocketStack
  instance stackv4v6
  instance unikernel

  connections Start {
    unikernel.stack -> stackv4v6.connect
  }
}

module Unikernel {
  passive component Main {
    async input port start: serial
    output port stack: serial
    param $port: U32 default 8080
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

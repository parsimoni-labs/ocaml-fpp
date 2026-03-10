module Unikernel {
  passive component Client {
    async input port start: serial
    output port http: serial
  }
}

instance unikernel: Unikernel.Client base id 0

topology UnixHttpFetch {
  import SocketStack
  instance stackv4v6
  instance resolver_unix
  instance conduit_tcp
  instance cohttp_client
  instance unikernel

  connections Start {
    resolver_unix.stack -> stackv4v6.connect
    conduit_tcp.stack -> stackv4v6.connect
    cohttp_client.resolver -> resolver_unix.connect
    cohttp_client.conduit -> conduit_tcp.start
    unikernel.http -> cohttp_client.ctx
  }
}

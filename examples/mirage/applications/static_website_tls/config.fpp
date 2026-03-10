module Dispatch {
  passive component HTTPS {
    async input port start: serial
    output port data: serial
    output port keys: serial
    output port http: serial
  }
}

instance static_data: Kv base id 0
instance tls_keys: Kv base id 0
instance conduit_tcp: Conduit_tcp.Make base id 0
instance cohttp_server: Cohttp_mirage.Server.Make base id 0
instance unikernel: Dispatch.HTTPS base id 0

topology UnixStaticWebsiteTls {
  import SocketStack
  instance stackv4v6
  instance conduit_tcp
  instance cohttp_server
  instance static_data
  instance tls_keys
  instance unikernel

  connections Start {
    conduit_tcp.stack -> stackv4v6.connect
    cohttp_server.conduit -> conduit_tcp.start
    unikernel.data -> static_data.connect
    unikernel.keys -> tls_keys.connect
    unikernel.http -> cohttp_server.listen
  }
}

module Dispatch {
  passive component HTTPS {
    sync input port start: serial
    output port data: serial
    output port keys: serial
    output port stack: serial
  }
}

instance static_data: Kv base id 0
instance tls_keys: Kv base id 0
instance unikernel: Dispatch.HTTPS base id 0

topology UnixStaticWebsiteTls {
  import SocketStack
  instance stackv4v6
  instance static_data
  instance tls_keys
  instance unikernel

  connections Start {
    unikernel.data -> static_data.connect
    unikernel.keys -> tls_keys.connect
    unikernel.stack -> stackv4v6.connect
  }
}

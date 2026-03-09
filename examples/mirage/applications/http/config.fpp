module Unikernel {
  passive component Make {
    sync input port start: serial
    output port certs: serial
    output port keys: serial
    output port tcp: serial
    output port conn: serial
    output port http: serial
  }
}

instance certs_data: Kv base id 0
instance keys_data: Kv base id 0
instance unikernel: Unikernel.Make base id 0

topology UnixHttp {
  import SocketStack
  instance stackv4v6
  instance happy_eyeballs_mirage
  instance dns_client
  instance certs_data
  instance keys_data
  instance paf_server
  instance unikernel

  connections Connect_device {
    happy_eyeballs_mirage.stack -> stackv4v6.connect
  }

  connections Start {
    dns_client.stack -> stackv4v6.connect
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
    unikernel.certs -> certs_data.connect
    unikernel.keys -> keys_data.connect
    unikernel.http -> paf_server.connect
  }
}

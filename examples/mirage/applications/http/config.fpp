module Connect {
  passive component Make {
    async input port connect: serial
    output port _tcp: serial
    output port he: serial
  }
}

module Unikernel {
  passive component Make {
    async input port start: serial
    output port certs: serial
    output port keys: serial
    output port tcp: serial
    output port conn: serial
    output port http: serial
    param tls: bool default false
    param tlsPort: U32 default 4343
    external param alpn: string
  }
}

instance certs_data: Kv base id 0
instance keys_data: Kv base id 0
instance connect: Connect.Make base id 0
instance http_server: Paf_mirage.Make base id 0
instance unikernel: Unikernel.Make base id 0

topology UnixHttp {
  import SocketStack
  instance stackv4v6
  instance tcpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
  instance happy_eyeballs_mirage
  instance dns_client
  instance mimic_happy_eyeballs
  instance certs_data
  instance keys_data
  instance connect
  instance http_server($port = 8080)
  instance unikernel

  connections Connect_device {
    happy_eyeballs_mirage.stack -> stackv4v6.connect
  }

  connections Start {
    dns_client.stack -> stackv4v6.connect
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
    mimic_happy_eyeballs._stack -> stackv4v6.connect
    mimic_happy_eyeballs.happy_eyeballs -> happy_eyeballs_mirage.connect_device
    mimic_happy_eyeballs._dns -> dns_client.start
    connect._tcp -> tcpv4v6_socket.connect
    connect.he -> mimic_happy_eyeballs.connect
    http_server.tcp -> tcpv4v6_socket.connect
    unikernel.certs -> certs_data.connect
    unikernel.keys -> keys_data.connect
    unikernel.tcp -> tcpv4v6_socket.connect
    unikernel.conn -> connect.connect
    unikernel.http -> http_server.init
  }
}

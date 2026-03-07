module Unikernel {
  passive component Make {
    sync input port start: serial
    output port dns: serial
  }
}

instance app: Unikernel.Make base id 0

topology UnixDns {
  import SocketStack
  instance stackv4v6
  instance happy_eyeballs_mirage
  instance dns_client
  instance app

  connections Connect_device {
    happy_eyeballs_mirage.stack -> stackv4v6.connect
  }

  connections Start {
    dns_client.stack -> stackv4v6.connect
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
    app.dns -> dns_client.start
  }
}

module Unikernel {
  passive component Make {
    async input port start: serial
    output port dns: serial
    external param domainName: string
  }
}

instance unikernel: Unikernel.Make base id 0

topology UnixDns {
  import SocketStack
  instance stackv4v6
  instance happy_eyeballs_mirage
  instance dns_client
  instance unikernel

  connections Connect_device {
    happy_eyeballs_mirage.stack -> stackv4v6.connect
  }

  connections Start {
    dns_client.stack -> stackv4v6.connect
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
    unikernel.dns -> dns_client.start
  }
}

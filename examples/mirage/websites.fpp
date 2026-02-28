@ MirageOS web-server topologies.
@
@ Each top-level topology is one deployment variant.
@ Sub-topologies are shared via [import]; the parent wires
@ any missing connections (which stack, which KV backend).

@ ── Vnetif topologies (Xen, Solo5, test) ────────────────

@ Crunch KV (build-time embedded), no DNS.
topology StaticWebsite {
  import TcpipStack
  instance data
  instance certs
  instance dispatch

  connections Start {
    dispatch.data -> data.connect
    dispatch.certs -> certs.connect
    dispatch.stack -> stack.connect
  }
}

@ Crunch KV, with DNS.
topology StaticWebsiteWithDns {
  import TcpipStack
  import DnsStack
  instance data
  instance certs
  instance dispatch

  connections Connect_device {
    happy_eyeballs.stack -> stack.connect
  }

  connections Connect {
    dns_client.stack -> stack.connect
  }

  connections Start {
    dispatch.data -> data.connect
    dispatch.certs -> certs.connect
    dispatch.stack -> stack.connect
  }
}

@ Tar-over-block KV, with DNS.
@ Each KV store reads from its own block device.
topology TarWebsite {
  import TcpipStack
  import DnsStack
  instance data_block
  instance certs_block
  instance tar_data
  instance tar_certs
  instance dispatch

  connections Connect_device {
    happy_eyeballs.stack -> stack.connect
  }

  connections Connect {
    dns_client.stack -> stack.connect
    tar_data.block -> data_block.connect
    tar_certs.block -> certs_block.connect
  }

  connections Start {
    dispatch.data -> tar_data.connect
    dispatch.certs -> tar_certs.connect
    dispatch.stack -> stack.connect
  }
}

@ FAT-over-block KV, no DNS.
topology FatWebsite {
  import TcpipStack
  instance data_block
  instance certs_block
  instance fat_data
  instance fat_certs
  instance dispatch

  connections Connect {
    fat_data.block -> data_block.connect
    fat_certs.block -> certs_block.connect
  }

  connections Start {
    dispatch.data -> fat_data.connect
    dispatch.certs -> fat_certs.connect
    dispatch.stack -> stack.connect
  }
}

@ ── Unix topologies ─────────────────────────────────────

@ Unix socket stack, crunch KV bound to concrete modules.
@ Runtime kwargs inject [~ipv4_only] and [~ipv6_only] into
@ socket connect calls.
topology UnixWebsite {
  import SocketStack
  @ ocaml.module Server.Runtime
  instance runtime
  @ ocaml.module Server.Udpv4v6_socket
  instance udpv4v6_socket
  @ ocaml.module Server.Tcpv4v6_socket
  instance tcpv4v6_socket
  @ ocaml.module Server.Stackv4v6
  instance stackv4v6
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs
  instance dispatch

  connections Start {
    dispatch.data -> data.connect
    dispatch.certs -> certs.connect
    dispatch.stack -> stackv4v6.connect
  }
}

@ Unix socket stack, crunch KV, with DNS.
@ Happy Eyeballs uses [connect_device] for initialisation.
topology UnixWebsiteWithDns {
  import SocketStack
  @ ocaml.module Server.Runtime
  instance runtime
  @ ocaml.module Server.Udpv4v6_socket
  instance udpv4v6_socket
  @ ocaml.module Server.Tcpv4v6_socket
  instance tcpv4v6_socket
  @ ocaml.module Server.Stackv4v6
  instance stackv4v6
  import DnsStack
  @ ocaml.functor Server.Dns
  instance dns_client
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs
  instance dispatch

  connections Connect_device {
    happy_eyeballs.stack -> stackv4v6.connect
  }

  connections Connect {
    dns_client.stack -> stackv4v6.connect
  }

  connections Start {
    dispatch.data -> data.connect
    dispatch.certs -> certs.connect
    dispatch.stack -> stackv4v6.connect
  }
}

@ Unix socket stack, in-memory KV (for testing).
topology UnixTestWebsite {
  import SocketStack
  @ ocaml.module Server.Runtime
  instance runtime
  @ ocaml.module Server.Udpv4v6_socket
  instance udpv4v6_socket
  @ ocaml.module Server.Tcpv4v6_socket
  instance tcpv4v6_socket
  @ ocaml.module Server.Stackv4v6
  instance stackv4v6
  @ ocaml.module Mirage_kv_mem
  instance data
  @ ocaml.module Mirage_kv_mem
  instance certs
  instance dispatch

  connections Start {
    dispatch.data -> data.connect
    dispatch.certs -> certs.connect
    dispatch.stack -> stackv4v6.connect
  }
}

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
  instance server

  connections Connect {
    server.data -> data.connect
    server.certs -> certs.connect
    server.stack -> stack.connect
  }
}

@ Crunch KV, with DNS.
topology StaticWebsiteWithDns {
  import TcpipStack
  import DnsStack
  instance data
  instance certs
  instance server

  connections Connect {
    happy_eyeballs.stack -> stack.connect
    dns_client.stack -> stack.connect
    server.data -> data.connect
    server.certs -> certs.connect
    server.stack -> stack.connect
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
  instance server

  connections Connect {
    happy_eyeballs.stack -> stack.connect
    dns_client.stack -> stack.connect
    tar_data.block -> data_block.connect
    tar_certs.block -> certs_block.connect
    server.data -> tar_data.connect
    server.certs -> tar_certs.connect
    server.stack -> stack.connect
  }
}

@ FAT-over-block KV, no DNS.
topology FatWebsite {
  import TcpipStack
  instance data_block
  instance certs_block
  instance fat_data
  instance fat_certs
  instance server

  connections Connect {
    fat_data.block -> data_block.connect
    fat_certs.block -> certs_block.connect
    server.data -> fat_data.connect
    server.certs -> fat_certs.connect
    server.stack -> stack.connect
  }
}

@ ── Unix topologies ─────────────────────────────────────

@ Unix socket stack, crunch KV bound to concrete modules.
topology UnixWebsite {
  import SocketStack
  @ ocaml.module Server.Udp_socket
  instance udp_socket
  @ ocaml.module Server.Tcp_socket
  instance tcp_socket
  @ ocaml.module Server.Socket_stack
  instance socket_stack
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs
  instance server

  connections Connect {
    server.data -> data.connect
    server.certs -> certs.connect
    server.stack -> socket_stack.connect
  }
}

@ Unix socket stack, crunch KV, with DNS.
@ Happy Eyeballs uses [connect_device] for initialisation.
topology UnixWebsiteWithDns {
  import SocketStack
  @ ocaml.module Server.Udp_socket
  instance udp_socket
  @ ocaml.module Server.Tcp_socket
  instance tcp_socket
  @ ocaml.module Server.Socket_stack
  instance socket_stack
  import DnsStack
  @ ocaml.functor Server.Dns
  instance dns_client
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs
  instance server

  connections Connect_device {
    happy_eyeballs.stack -> socket_stack.connect
  }

  connections Connect {
    dns_client.stack -> socket_stack.connect
    server.data -> data.connect
    server.certs -> certs.connect
    server.stack -> socket_stack.connect
  }
}

@ Unix socket stack, in-memory KV (for testing).
topology UnixTestWebsite {
  import SocketStack
  @ ocaml.module Server.Udp_socket
  instance udp_socket
  @ ocaml.module Server.Tcp_socket
  instance tcp_socket
  @ ocaml.module Server.Socket_stack
  instance socket_stack
  @ ocaml.module Mirage_kv_mem
  instance data
  @ ocaml.module Mirage_kv_mem
  instance certs
  instance server

  connections Connect {
    server.data -> data.connect
    server.certs -> certs.connect
    server.stack -> socket_stack.connect
  }
}

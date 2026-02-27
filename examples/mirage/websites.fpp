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
    server.data -> data.get
    server.certs -> certs.get
    server.stack -> stack.disconnect
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
    happy_eyeballs.stack -> stack.disconnect
    dns_client.stack -> stack.disconnect
    server.data -> data.get
    server.certs -> certs.get
    server.stack -> stack.disconnect
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
    happy_eyeballs.stack -> stack.disconnect
    dns_client.stack -> stack.disconnect
    tar_data.block -> data_block.read
    tar_certs.block -> certs_block.read
    server.data -> tar_data.disconnect
    server.certs -> tar_certs.disconnect
    server.stack -> stack.disconnect
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
    fat_data.block -> data_block.read
    fat_certs.block -> certs_block.read
    server.data -> fat_data.disconnect
    server.certs -> fat_certs.disconnect
    server.stack -> stack.disconnect
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
    server.data -> data.get
    server.certs -> certs.get
    server.stack -> socket_stack.disconnect
  }
}

@ Unix socket stack, crunch KV, with DNS.
topology UnixWebsiteWithDns {
  import SocketStack
  @ ocaml.module Server.Udp_socket
  instance udp_socket
  @ ocaml.module Server.Tcp_socket
  instance tcp_socket
  @ ocaml.module Server.Socket_stack
  instance socket_stack
  import DnsStack
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs
  instance server

  connections Connect {
    happy_eyeballs.stack -> socket_stack.disconnect
    dns_client.stack -> socket_stack.disconnect
    server.data -> data.get
    server.certs -> certs.get
    server.stack -> socket_stack.disconnect
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
    server.data -> data.get
    server.certs -> certs.get
    server.stack -> socket_stack.disconnect
  }
}

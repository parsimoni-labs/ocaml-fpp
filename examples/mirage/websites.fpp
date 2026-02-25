@ MirageOS web-server topologies.
@
@ Each top-level topology is one deployment variant.
@ Sub-topologies are shared via [import]; the parent wires
@ any missing connections (which stack, which KV backend).

@ ── Vnetif topologies (Xen, Solo5, test) ────────────────

@ Crunch KV (build-time embedded), no DNS.
topology StaticWebsite {
  import TcpipStack
  import HttpStack
  instance data
  instance certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
  }
}

@ Crunch KV, with DNS.
topology StaticWebsiteWithDns {
  import TcpipStack
  import HttpStack
  import DnsStack
  instance data
  instance certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
    happy_eyeballs.stack -> stack.provide
    dns_client.stack -> stack.provide
  }
}

@ Tar-over-block KV, with DNS.
@ Each KV store reads from its own block device.
topology TarWebsite {
  import TcpipStack
  import HttpStack
  import DnsStack
  instance data_block
  instance certs_block
  instance tar_data
  instance tar_certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
    happy_eyeballs.stack -> stack.provide
    dns_client.stack -> stack.provide
    tar_data.block -> data_block.provide
    tar_certs.block -> certs_block.provide
  }
}

@ FAT-over-block KV, no DNS.
topology FatWebsite {
  import TcpipStack
  import HttpStack
  instance data_block
  instance certs_block
  instance fat_data
  instance fat_certs

  connections Connect {
    conduit_tcp.stack -> stack.provide
    fat_data.block -> data_block.provide
    fat_certs.block -> certs_block.provide
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
  import HttpStack
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs

  connections Connect {
    conduit_tcp.stack -> socket_stack.provide
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
  import HttpStack
  import DnsStack
  @ ocaml.module Htdocs_data
  instance data
  @ ocaml.module Tls_data
  instance certs

  connections Connect {
    conduit_tcp.stack -> socket_stack.provide
    happy_eyeballs.stack -> socket_stack.provide
    dns_client.stack -> socket_stack.provide
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
  import HttpStack
  @ ocaml.module Mirage_kv_mem
  instance data
  @ ocaml.module Mirage_kv_mem
  instance certs

  connections Connect {
    conduit_tcp.stack -> socket_stack.provide
  }
}

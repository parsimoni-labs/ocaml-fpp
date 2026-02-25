@ mirage-skeleton example topologies.
@
@ Minimal topologies matching the mirage-skeleton tutorial
@ and device-usage examples, for comparison with Mirage's
@ generated main.ml.

@ device-usage/network: plain socket stack, no HTTP.
@ Mirage: [Unikernel.Main(Tcpip_stack_socket.V4V6)]
topology UnixNetwork {
  @ ocaml.module Tcpip_stack_socket.V4V6
  instance socket_stack

  connections Connect {}
}

@ device-usage/kv_ro: single crunch KV store.
@ Mirage: [Unikernel.Main(Static_t)]
topology UnixKv {
  @ ocaml.module Static_t
  instance data

  connections Connect {}
}

@ applications/dns: socket stack with Happy Eyeballs + DNS client.
@ Mirage: [Happy_eyeballs_mirage.Make(Stack)]
@         [Dns_client_mirage.Make(Stack)(HE)]
@         [Unikernel.Make(Dns)]
topology UnixDnsResolver {
  @ ocaml.module Tcpip_stack_socket.V4V6
  instance socket_stack
  import DnsStack

  connections Connect {
    happy_eyeballs.stack -> socket_stack.provide
    dns_client.stack -> socket_stack.provide
  }
}

@ applications/static_website_tls: HTTPS server with two KV stores.
@ Mirage: [Conduit_mirage.TCP(Stack)]
@         [Conduit_mirage.TLS(Conduit_tcp)]
@         [Cohttp_mirage.Server.Make(Conduit_tls)]
@         [Dispatch.HTTPS(Static_htdocs)(Static_tls)(Server)]
topology UnixStaticWebsiteTls {
  @ ocaml.module Tcpip_stack_socket.V4V6
  instance socket_stack
  import HttpStack
  @ ocaml.module Static_htdocs
  instance data
  @ ocaml.module Static_tls
  instance certs

  connections Connect {
    conduit_tcp.stack -> socket_stack.provide
  }
}

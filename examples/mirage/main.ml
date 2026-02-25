(* main.ml — Static HTTPS website over Unix sockets.

   Provides the concrete leaf implementations for the FPP-generated
   [UnixWebsite] topology and starts the HTTPS server.

   The socket stack binds to real host ports, so the server is
   reachable via [curl -k https://localhost:443]. *)

module Stack =
  Mirage.UnixWebsite.Make (Tcpip_stack_socket.V4V6) (Htdocs_data) (Tls_data)

module Srv = Server.HTTPS (Htdocs_data) (Tls_data) (Stack.Http)

let () =
  Mirage_crypto_rng_unix.use_default ();
  Logs.set_level (Some Info);
  Logs.set_reporter (Logs_fmt.reporter ());
  Lwt_main.run
    begin
      let open Lwt.Syntax in
      let* data = Htdocs_data.connect () in
      let* certs = Tls_data.connect () in
      let ipv4 = Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0" in
      let* tcp =
        Tcpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false ipv4 None
      in
      let* udp =
        Udpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false ipv4 None
      in
      let* socket_stack = Tcpip_stack_socket.V4V6.connect udp tcp in
      Srv.start data certs (Stack.Http.listen socket_stack)
    end

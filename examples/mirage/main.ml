(* main.ml — Static HTTPS website demo over virtual ethernet.

   Uses the FPP-generated [StaticWebsite] topology to assemble a full
   MirageOS TCP/IP stack with HTTPS serving.  A test client on the same
   virtual network performs a TLS handshake, sends an HTTP GET request,
   and prints the response — proving the entire chain works end-to-end.

   The network backend is vnetif (in-memory Ethernet).  For deployment,
   replace [Net] with the target-specific implementation:
   - [mirage-net-unix]  (tap device)
   - [mirage-net-solo5]  (virtio / hvt)
   - [mirage-net-xen]  (Xen netfront) *)

open Lwt.Infix

(* {1 Network backend} *)

module B = Basic_backend.Make
module Net = Vnetif.Make (B)

(* {1 FPP-generated topology wiring}

   One functor application replaces a manual chain of 7+ module
   applications. *)

module Stack = Mirage.StaticWebsite.Make (Net) (Htdocs_data) (Tls_data)

(* Separate TCP/IP stack for the test client. *)
module Client = Mirage.TcpipStack.Make (Net)
module Client_tls = Tls_mirage.Make (Client.Tcp)

(* {1 Configuration} *)

let server_ip = Ipaddr.V4.of_string_exn "10.0.0.2"
let server_cidr = Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24"
let client_cidr = Ipaddr.V4.Prefix.of_string_exn "10.0.0.3/24"

(* {1 Packet input chain}

   In a MirageOS unikernel the runtime drives the packet input loop.
   Here we wire it explicitly: Net -> Ethernet -> {ARP, IPv4 -> {TCP, UDP}}. *)

let noop_udp ~src:_ ~dst:_ _ = Lwt.return_unit
let noop_default ~proto:_ ~src:_ ~dst:_ _ = Lwt.return_unit

let listen_server (s : Stack.t) =
  Net.listen s.net ~header_size:Ethernet.Packet.sizeof_ethernet (fun buf ->
      Stack.Eth.input ~arpv4:(Stack.Arp.input s.arp)
        ~ipv4:
          (Stack.Ipv4.input s.ipv4 ~tcp:(Stack.Tcp.input s.tcp) ~udp:noop_udp
             ~default:noop_default)
        ~ipv6:(fun _ -> Lwt.return_unit)
        s.eth buf)

let listen_client (c : Client.t) =
  Net.listen c.net ~header_size:Ethernet.Packet.sizeof_ethernet (fun buf ->
      Client.Eth.input ~arpv4:(Client.Arp.input c.arp)
        ~ipv4:
          (Client.Ipv4.input c.ipv4 ~tcp:(Client.Tcp.input c.tcp)
             ~udp:(Client.Udp.input c.udp) ~default:noop_default)
        ~ipv6:(fun _ -> Lwt.return_unit)
        c.eth buf)

(* {1 Server: HTTPS and HTTP redirect}

   The topology generates the TLS and CoHTTP modules; main.ml handles
   TCP listening and TLS handshake, matching what Functoria does in real
   MirageOS deployments. *)

let https_src = Logs.Src.create "https" ~doc:"HTTPS server"

module Https_log = (val Logs.src_log https_src : Logs.LOG)

let http_src = Logs.Src.create "http" ~doc:"HTTP server"

module Http_log = (val Logs.src_log http_src : Logs.LOG)

let start_server (stack : Stack.t) =
  let https_handler = Stack.Server.handler stack.server in
  let tls_cfg = Stack.Server.tls_config stack.server in
  (* HTTPS: accept TCP, do TLS handshake, serve via CoHTTP *)
  Https_log.info (fun f -> f "listening on 443/TCP (HTTPS)");
  Stack.Tcp.listen stack.tcp ~port:443 (fun flow ->
      Stack.Tls.server_of_flow tls_cfg flow >>= function
      | Error e ->
          Https_log.warn (fun f ->
              f "TLS handshake failed: %a" Stack.Tls.pp_write_error e);
          Lwt.return_unit
      | Ok tls_flow -> Stack.Https_srv.callback https_handler tls_flow);
  (* HTTP redirect: plain TCP -> 301 to HTTPS *)
  Http_log.info (fun f -> f "listening on 80/TCP (HTTP redirect)");
  let redirect_callback (_, _cid) request _body =
    let uri = Cohttp.Request.uri request in
    let new_uri = Uri.with_scheme uri (Some "https") in
    let new_uri = Uri.with_port new_uri (Some 443) in
    let headers = Cohttp.Header.init_with "location" (Uri.to_string new_uri) in
    Stack.Http_srv.respond ~headers ~status:`Moved_permanently ~body:`Empty ()
  in
  let redirect_handler = Stack.Http_srv.make ~callback:redirect_callback () in
  Stack.Tcp.listen stack.tcp ~port:80 (fun flow ->
      Stack.Http_srv.callback redirect_handler flow);
  Lwt.return_unit

(* {1 Test client} *)

let test_client backend =
  let open Lwt.Syntax in
  let* client_net = Net.connect backend in
  let* client = Client.connect ~cidr:client_cidr client_net in
  (* Start client packet processing in the background. *)
  Lwt.async (fun () ->
      listen_client client >|= function
      | Ok () -> ()
      | Error e -> Fmt.pr "client: %a\n%!" Net.pp_error e);
  (* Wait for ARP resolution. *)
  let* () = Lwt_unix.sleep 0.5 in
  Printf.printf "Client: connecting to %s:443...\n%!"
    (Ipaddr.V4.to_string server_ip);
  let* tcp_result = Client.Tcp.create_connection client.tcp (server_ip, 443) in
  match tcp_result with
  | Error e ->
      Fmt.pr "Client: TCP failed: %a\n%!" Client.Tcp.pp_error e;
      Lwt.return_unit
  | Ok tcp_flow ->
      Printf.printf "Client: TCP connected, starting TLS handshake...\n%!";
      let null_auth ?ip:_ ~host:_ _certs = Ok None in
      let tls_config =
        Result.get_ok (Tls.Config.client ~authenticator:null_auth ())
      in
      let* tls_result = Client_tls.client_of_flow tls_config tcp_flow in
      begin match tls_result with
      | Error e ->
          Fmt.pr "Client: TLS failed: %a\n%!" Client_tls.pp_write_error e;
          Lwt.return_unit
      | Ok tls_flow ->
          Printf.printf "Client: TLS established, sending GET /...\n%!";
          let request =
            "GET / HTTP/1.1\r\nHost: 10.0.0.2\r\nConnection: close\r\n\r\n"
          in
          let* _ = Client_tls.write tls_flow (Cstruct.of_string request) in
          let* resp = Client_tls.read tls_flow in
          begin match resp with
          | Ok (`Data buf) ->
              Printf.printf "Client: got %d bytes:\n%s\n%!" (Cstruct.length buf)
                (Cstruct.to_string buf)
          | Ok `Eof -> Printf.printf "Client: connection closed (no data)\n%!"
          | Error e -> Fmt.pr "Client: read error: %a\n%!" Client_tls.pp_error e
          end;
          Client_tls.close tls_flow
      end

(* {1 Entry point} *)

let () =
  Mirage_crypto_rng_unix.use_default ();
  Logs.set_level (Some Info);
  Logs.set_reporter (Logs_fmt.reporter ());
  Lwt_main.run
    begin
      let open Lwt.Syntax in
      (* KV stores from crunched directories. *)
      let* data = Htdocs_data.connect () in
      let* certs = Tls_data.connect () in
      (* Virtual ethernet backend (shared by server and client). *)
      let backend = B.create () in
      (* Server: assemble the full stack via FPP topology. *)
      let* server_net = Net.connect backend in
      let* stack = Stack.connect ~cidr:server_cidr server_net data certs in
      let* () = start_server stack in
      (* Start server packet processing in the background. *)
      Lwt.async (fun () ->
          listen_server stack >|= function
          | Ok () -> ()
          | Error e -> Fmt.pr "server: %a\n%!" Net.pp_error e);
      Printf.printf "Server: HTTPS listening on %s:443\n%!"
        (Ipaddr.V4.to_string server_ip);
      (* Run the test client. *)
      test_client backend
    end

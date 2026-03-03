(* server.ml — HTTPS server with HTTP redirect.

   Adapted from mirage-skeleton/static_website_tls/dispatch.ml.
   Uses conduit for unified TLS/TCP transport, so one CoHTTP
   server module handles both HTTPS dispatch and HTTP redirect.

   The conduit and CoHTTP modules are created internally from
   the TCP/IP stack — matching the mirage-skeleton convention
   where these are not separate devices. *)

open Lwt.Infix
open Cmdliner

let http_port =
  let doc = Arg.info ~doc:"Listening HTTP port." [ "http" ] in
  Mirage_runtime.register_arg Arg.(value & opt int 80 doc)

let https_port =
  let doc = Arg.info ~doc:"Listening HTTPS port." [ "https" ] in
  Mirage_runtime.register_arg Arg.(value & opt int 443 doc)

module type HTTP = Cohttp_mirage.Server.S

(* Logging *)
let https_src = Logs.Src.create "https" ~doc:"HTTPS server"

module Https_log = (val Logs.src_log https_src : Logs.LOG)

let http_src = Logs.Src.create "http" ~doc:"HTTP server"

module Http_log = (val Logs.src_log http_src : Logs.LOG)

(* ── Socket wrappers ───────────────────────────────────
   Adapt real library connect signatures to the
   [connect ~ipv4_only ~ipv6_only () : t Lwt.t] convention. *)

module Udpv4v6_socket = struct
  include Udpv4v6_socket

  let connect ~ipv4_only ~ipv6_only () =
    let ipv4 = Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0" in
    Udpv4v6_socket.connect ~ipv4_only ~ipv6_only ipv4 None
end

module Tcpv4v6_socket = struct
  include Tcpv4v6_socket

  let connect ~ipv4_only ~ipv6_only () =
    let ipv4 = Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0" in
    Tcpv4v6_socket.connect ~ipv4_only ~ipv6_only ipv4 None
end

module Stackv4v6 = struct
  include Tcpip_stack_socket.V4V6

  let connect (udp : Udpv4v6_socket.t) (tcp : Tcpv4v6_socket.t) =
    Tcpip_stack_socket.V4V6.connect udp tcp
end

(* ── DNS client wrapper ────────────────────────────────
   The real connect takes (stack, he) as a tuple;
   the wrapper takes them as two positional arguments. *)

module Dns
    (S : Tcpip.Stack.V4V6)
    (H :
      Happy_eyeballs_mirage.S with type stack = S.t and type flow = S.TCP.flow) =
struct
  module D = Dns_client_mirage.Make (S) (H)
  include D

  let connect ?nameservers ?timeout ?cache_size (s : S.t) (h : H.t) : D.t Lwt.t
      =
    D.connect ?nameservers ?timeout ?cache_size (s, h)
end

(* ── Dispatch ──────────────────────────────────────────
   Takes KV stores and TCP/IP stack; creates conduit and CoHTTP
   modules internally (no separate conduit/http devices needed). *)

module Dispatch (FS : Mirage_kv.RO) (S : HTTP) = struct
  let failf fmt = Fmt.kstr Lwt.fail_with fmt

  let rec dispatcher fs uri =
    match Uri.path uri with
    | "" | "/" -> dispatcher fs (Uri.with_path uri "index.html")
    | path ->
        let header =
          Cohttp.Header.init_with "Strict-Transport-Security" "max-age=31536000"
        in
        let mimetype = Magic_mime.lookup path in
        let headers = Cohttp.Header.add header "content-type" mimetype in
        Lwt.catch
          (fun () ->
            FS.get fs (Mirage_kv.Key.v path) >>= function
            | Error e -> failf "get: %a" FS.pp_error e
            | Ok body -> S.respond_string ~status:`OK ~body ~headers ())
          (fun _exn -> S.respond_not_found ())

  let redirect port uri =
    let new_uri = Uri.with_scheme uri (Some "https") in
    let new_uri = Uri.with_port new_uri (Some port) in
    Http_log.info (fun f ->
        f "[%s] -> [%s]" (Uri.to_string uri) (Uri.to_string new_uri));
    let headers = Cohttp.Header.init_with "location" (Uri.to_string new_uri) in
    S.respond ~headers ~status:`Moved_permanently ~body:`Empty ()

  let serve dispatch =
    let callback (_, cid) request _body =
      let uri = Cohttp.Request.uri request in
      let cid =
        begin[@alert "-deprecated"]
          Cohttp.Connection.to_string cid
        end
      in
      Https_log.info (fun f -> f "[%s] serving %s." cid (Uri.to_string uri));
      dispatch uri
    in
    let conn_closed (_, cid) =
      let cid =
        begin[@alert "-deprecated"]
          Cohttp.Connection.to_string cid
        end
      in
      Https_log.info (fun f -> f "[%s] closing" cid)
    in
    S.make ~conn_closed ~callback ()
end

module HTTPS (DATA : Mirage_kv.RO) (KEYS : Mirage_kv.RO) (Http : HTTP) = struct
  module X509 = Tls_mirage.X509 (KEYS)
  module D = Dispatch (DATA) (Http)

  let tls_init kv =
    X509.certificate kv `Default >>= fun cert ->
    let conf =
      Result.get_ok (Tls.Config.server ~certificates:(`Single cert) ())
    in
    Lwt.return conf

  let start data keys http =
    tls_init keys >>= fun cfg ->
    let https_p = https_port () in
    let http_p = http_port () in
    let tls = `TLS (cfg, `TCP https_p) in
    let tcp = `TCP http_p in
    let https =
      Https_log.info (fun f -> f "listening for HTTPS on %d/TCP" https_p);
      http tls @@ D.serve (D.dispatcher data)
    in
    let http =
      Http_log.info (fun f -> f "listening for HTTP on %d/TCP" http_p);
      http tcp @@ D.serve (D.redirect https_p)
    in
    Lwt.join [ https; http ]
end

(* Wrapper for FPP codegen: takes Stack, builds conduit/CoHTTP chain,
   applies HTTPS with the resulting listen function. *)
module Make_dispatch
    (DATA : Mirage_kv.RO)
    (KEYS : Mirage_kv.RO)
    (Stack : Tcpip.Stack.V4V6) =
struct
  module CT = Conduit_mirage.TCP (Stack)
  module C = Conduit_mirage.TLS (CT)
  module Http = Cohttp_mirage.Server.Make (C)
  module H = HTTPS (DATA) (KEYS) (Http)

  let start data keys stack = H.start data keys (Http.listen stack)
end

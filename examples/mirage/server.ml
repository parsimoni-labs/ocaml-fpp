(* server.ml — HTTPS server with HTTP redirect.

   Adapted from mirage-skeleton/static_website_tls/dispatch.ml.
   Uses conduit for unified TLS/TCP transport, so one CoHTTP
   server module handles both HTTPS dispatch and HTTP redirect. *)

open Lwt.Infix

module type HTTP = Cohttp_mirage.Server.S

(* Logging *)
let https_src = Logs.Src.create "https" ~doc:"HTTPS server"

module Https_log = (val Logs.src_log https_src : Logs.LOG)

let http_src = Logs.Src.create "http" ~doc:"HTTP server"

module Http_log = (val Logs.src_log http_src : Logs.LOG)

module Dispatch (FS : Mirage_kv.RO) (S : HTTP) = struct
  let failf fmt = Fmt.kstr Lwt.fail_with fmt

  (* Given a URI, find the appropriate file and construct a response. *)
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

  (* Redirect to the same address, but in https. *)
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

module Udp_socket = struct
  include Udpv4v6_socket

  let connect () =
    let ipv4 = Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0" in
    Udpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false ipv4 None
end

module Tcp_socket = struct
  include Tcpv4v6_socket

  let connect () =
    let ipv4 = Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0" in
    Tcpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false ipv4 None
end

module Socket_stack = struct
  include Tcpip_stack_socket.V4V6

  let connect (udp : Udp_socket.t) (tcp : Tcp_socket.t) =
    Tcpip_stack_socket.V4V6.connect udp tcp
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
    let tls = `TLS (cfg, `TCP 443) in
    let tcp = `TCP 80 in
    let https =
      Https_log.info (fun f -> f "listening for HTTPS on 443/TCP");
      http tls @@ D.serve (D.dispatcher data)
    in
    let http =
      Http_log.info (fun f -> f "listening for HTTP on 80/TCP");
      http tcp @@ D.serve (D.redirect 443)
    in
    Lwt.join [ https; http ]
end

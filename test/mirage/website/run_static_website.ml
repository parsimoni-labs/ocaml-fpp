(* Run the StaticWebsite parameterised topology end-to-end.

   Instantiates the generated functor with Basic_backend (in-memory
   vnetif) and Mirage_kv_mem, creates the full network stack on a
   virtual interface, and starts the (stub) HTTPS server. *)

module B = Basic_backend.Make
module W = Gen_static_website.Make (B) (Mirage_kv_mem) (Mirage_kv_mem)

let () = W.init ()

let () =
  Lwt_main.run
    begin
      let open Lwt.Syntax in
      let backend = B.create () in
      let cidr = Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24" in
      let* data = Mirage_kv_mem.connect () in
      let* certs = Mirage_kv_mem.connect () in
      let* c = W.connect ~cidr ~ipv4_only:false ~ipv6_only:false backend in
      let* _s = W.start c.stack data certs in
      Lwt.return ()
    end

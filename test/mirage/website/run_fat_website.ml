(* Run the FatWebsite parameterised topology end-to-end.

   Instantiates the generated functor with Basic_backend (in-memory
   vnetif), Ramdisk (zeroed in-memory block device), and the local
   Fat.KV_RO stub.  Creates the full network stack on a virtual
   interface and starts the (stub) HTTPS server. *)

module B = Basic_backend.Make
module W = Gen_fat_website.Make (B) (Ramdisk) (Ramdisk)

let () = W.init ()

let () =
  Lwt_main.run
    begin
      let open Lwt.Syntax in
      let backend = B.create () in
      let cidr = Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24" in
      let* data_block = Ramdisk.connect () in
      let* certs_block = Ramdisk.connect () in
      let* c =
        W.connect ~cidr ~ipv4_only:false ~ipv6_only:false backend data_block
          certs_block
      in
      let* _s = W.start c.stack c.fat_data c.fat_certs in
      Lwt.return ()
    end

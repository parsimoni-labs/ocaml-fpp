(* Compilation-test stub for the Fat module.

   fat-filesystem requires mirage-kv < 5, which conflicts with the
   current mirage-kv >= 6.  This stub provides the [KV_RO] functor
   signature that the generated FatWebsite topology references. *)

module KV_RO (B : Mirage_block.S) = struct
  type t = unit

  let connect (_ : B.t) : t Lwt.t = Lwt.return_unit
end

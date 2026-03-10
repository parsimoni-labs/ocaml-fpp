(** Adapter for [Git.Mem.Store] — in-memory Git store with SHA1. *)

include Git.Mem.Store

let connect () =
  let open Lwt.Infix in
  v (Fpath.v ".") >|= function
  | Ok v -> v
  | Error err -> Fmt.failwith "%a" pp_error err

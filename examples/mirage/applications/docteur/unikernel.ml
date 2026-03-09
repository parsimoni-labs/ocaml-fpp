open Lwt.Infix
open Cmdliner

let filename =
  let doc = Arg.info ~doc:"The filename to print out." [ "filename" ] in
  Mirage_runtime.register_arg Arg.(value & opt string "/hello" doc)

module Make (Store : Mirage_kv.RO) = struct
  module Key = Mirage_kv.Key

  let start store =
    Store.get store (Key.v (filename ())) >|= function
    | Error err -> Logs.err (fun m -> m "Error: %a." Store.pp_error err)
    | Ok str -> Logs.info (fun m -> m "%s" str)
end

module Main (KV : Mirage_kv.RO) = struct
  let start kv =
    let open Lwt.Infix in
    KV.list kv Mirage_kv.Key.empty >|= function
    | Error e -> Logs.warn (fun f -> f "list error: %a" KV.pp_error e)
    | Ok entries ->
        Logs.info (fun f ->
            f "tar archive contains %d entries" (List.length entries))
end

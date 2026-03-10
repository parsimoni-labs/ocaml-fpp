open Lwt.Infix

let start ~hello =
  let rec loop = function
    | 0 -> Lwt.return_unit
    | n ->
        Logs.info (fun f -> f "%s" hello);
        Mirage_sleep.ns (Duration.of_sec 1) >>= fun () -> loop (n - 1)
  in
  loop 4

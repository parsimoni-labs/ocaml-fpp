include Basic_backend.Make

let connect () = Lwt.return (create ())

(** Adapter providing a [Mimic.ctx] for Git over Unix (TCP/HTTP/SSH). *)

let connect () = Git_unix.ctx (Happy_eyeballs_lwt.create ())

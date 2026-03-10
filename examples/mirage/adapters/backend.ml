(** Adapter: [Basic_backend.Make] — in-memory Ethernet switch for Vnetif.

    [Basic_backend.Make.create] is synchronous. We wrap it as [connect]
    returning [Lwt.t] so the FPP codegen can use it as a device constructor. *)

include Basic_backend.Make

let connect () = Lwt.return (create ())

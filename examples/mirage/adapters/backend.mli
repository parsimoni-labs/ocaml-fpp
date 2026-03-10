(** In-memory Ethernet switch for Vnetif. *)

include module type of struct
  include Basic_backend.Make
end

val connect : unit -> t Lwt.t

(** TCP conduit adapter. *)

module Make (S : Tcpip.Stack.V4V6) : sig
  include module type of struct
    include Conduit_mirage.TCP (S)
  end

  val start : S.t -> t Lwt.t
end

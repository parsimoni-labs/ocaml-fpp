(** Resolver adapter. *)

module Make (S : Tcpip.Stack.V4V6) : sig
  include module type of struct
    include Resolver_mirage.Make (S)
  end

  val connect : S.t -> t Lwt.t
end

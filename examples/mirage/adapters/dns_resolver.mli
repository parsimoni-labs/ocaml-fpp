(** DNS resolver adapter with unpacked arguments. *)

module Make
    (S : Tcpip.Stack.V4V6)
    (H :
      Happy_eyeballs_mirage.S with type stack = S.t and type flow = S.TCP.flow) : sig
  include module type of struct
    include Dns_client_mirage.Make (S) (H)
  end

  val start : S.t -> H.t -> t Lwt.t
end

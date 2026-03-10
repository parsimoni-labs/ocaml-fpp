(** Socket stack adapter with functor shell. *)

module Make (_ : sig end) (_ : sig end) : module type of Tcpip_stack_socket.V4V6

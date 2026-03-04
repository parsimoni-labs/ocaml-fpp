(** Adapter: [Tcpip_stack_socket.V4V6] with functor interface.

    [Tcpip_stack_socket.V4V6] is not a functor — it uses concrete socket
    implementations directly. This wrapper provides a functor shell so the FPP
    codegen can treat it uniformly with other stack components. *)

module Make (_ : sig end) (_ : sig end) = Tcpip_stack_socket.V4V6

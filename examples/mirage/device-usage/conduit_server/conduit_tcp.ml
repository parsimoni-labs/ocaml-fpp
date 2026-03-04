(** Adapter: [Conduit_mirage.TCP] with a standard device-init function.

    [Conduit_mirage.TCP(S).t = S.t] so the "connect" is identity — the stack
    value IS the conduit value. We expose [start] so the FPP codegen can call it
    as a normal device constructor. *)

module Make (S : Tcpip.Stack.V4V6) = struct
  include Conduit_mirage.TCP (S)

  let start s = Lwt.return s
end

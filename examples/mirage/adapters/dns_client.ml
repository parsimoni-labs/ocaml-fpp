(** Adapter: [Dns_client_mirage] with unpacked stack argument.

    [Dns_client_mirage.Make(S)(H).connect] takes a tuple [(S.t * H.t)] as its
    [Transport.stack] argument. We expose [start] so the FPP codegen can pass
    the stack and happy-eyeballs values as separate positional arguments. *)

module Make
    (S : Tcpip.Stack.V4V6)
    (H :
      Happy_eyeballs_mirage.S with type stack = S.t and type flow = S.TCP.flow) =
struct
  include Dns_client_mirage.Make (S) (H)

  let start s h = connect (s, h)
end

(** Adapter: [Dns_client_mirage.Make] with unpacked connect arguments.

    [Dns_client_mirage.Make(S)(H).connect] takes a [(S.t * H.t)] tuple. We
    expose [start] that takes the stack and happy-eyeballs as separate arguments
    so the FPP codegen can wire them from the connection graph. *)

module Make
    (S : Tcpip.Stack.V4V6)
    (H :
      Happy_eyeballs_mirage.S with type stack = S.t and type flow = S.TCP.flow) =
struct
  include Dns_client_mirage.Make (S) (H)

  let start ?cache_size ?edns ?nameservers ?timeout s h =
    connect ?cache_size ?edns ?nameservers ?timeout (s, h)
end

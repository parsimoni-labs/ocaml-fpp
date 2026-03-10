(** Adapter: [Resolver_mirage.Make] with [connect] for the FPP codegen.

    [Resolver_mirage.Make(S)] produces a resolver from a stack. We expose
    [connect] so that the FPP codegen can call it as a normal device
    constructor. The [v] function creates a resolver bound to the given stack.
*)

module Make (S : Tcpip.Stack.V4V6) = struct
  include Resolver_mirage.Make (S)

  let connect s =
    let open Lwt.Infix in
    v s >>= function Ok t -> Lwt.return t | Error (`Msg m) -> Lwt.fail_with m
end

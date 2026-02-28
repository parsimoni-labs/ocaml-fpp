(* Compilation-test stubs for the Server module.

   Mirrors the real examples/mirage/server.ml structure but with
   trivial implementations.  Socket wrappers match the connect
   signatures that ofpp generates. *)

module Runtime = struct
  let ipv4_only = false
  let ipv6_only = false
end

module Udpv4v6_socket = struct
  include Udpv4v6_socket

  let connect ~ipv4_only:_ ~ipv6_only:_ () : t Lwt.t = assert false
end

module Tcpv4v6_socket = struct
  include Tcpv4v6_socket

  let connect ~ipv4_only:_ ~ipv6_only:_ () : t Lwt.t = assert false
end

module Stackv4v6 = struct
  include Tcpip_stack_socket.V4V6

  let connect (_udp : Udpv4v6_socket.t) (_tcp : Tcpv4v6_socket.t) : t Lwt.t =
    assert false
end

module HTTPS (DATA : sig
  type t
end) (KEYS : sig
  type t
end) (Stack : sig
  type t
end) =
struct
  let start (_ : DATA.t) (_ : KEYS.t) (_ : Stack.t) : unit Lwt.t =
    Lwt.return_unit
end

(* DNS client wrapper: the real connect takes (stack, he) as a tuple;
   the wrapper takes them as two separate positional arguments. *)
module Dns
    (S : Tcpip.Stack.V4V6)
    (H :
      Happy_eyeballs_mirage.S with type stack = S.t and type flow = S.TCP.flow) =
struct
  module D = Dns_client_mirage.Make (S) (H)
  include D

  let connect (s : S.t) (h : H.t) : D.t Lwt.t = D.connect (s, h)
end

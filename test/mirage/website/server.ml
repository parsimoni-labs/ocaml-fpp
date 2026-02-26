(* Compilation-test stubs for the Server module.

   Mirrors the real examples/mirage/server.ml structure but with
   trivial implementations.  Socket wrappers match the connect
   signatures that ofpp generates. *)

module Udp_socket = struct
  include Udpv4v6_socket

  let connect () : t Lwt.t = assert false
end

module Tcp_socket = struct
  include Tcpv4v6_socket

  let connect () : t Lwt.t = assert false
end

module Socket_stack = struct
  include Tcpip_stack_socket.V4V6

  let connect (_udp : Udp_socket.t) (_tcp : Tcp_socket.t) : t Lwt.t =
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
  let connect (_ : DATA.t) (_ : KEYS.t) (_ : Stack.t) : unit Lwt.t =
    Lwt.return_unit
end

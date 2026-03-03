(* Test stubs for the Server module.

   Socket wrappers bridge the ofpp-generated [connect ~ipv4_only
   ~ipv6_only ()] signatures to the real tcpip socket APIs that also
   take IP prefix arguments.  Default addresses bind to [0.0.0.0/0]
   so no real ports are opened until [listen] is called. *)

let default_ipv4 = Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0"

module Udpv4v6_socket = struct
  include Udpv4v6_socket

  let connect ~ipv4_only ~ipv6_only () : t Lwt.t =
    Udpv4v6_socket.connect ~ipv4_only ~ipv6_only default_ipv4 None
end

module Tcpv4v6_socket = struct
  include Tcpv4v6_socket

  let connect ~ipv4_only ~ipv6_only () : t Lwt.t =
    Tcpv4v6_socket.connect ~ipv4_only ~ipv6_only default_ipv4 None
end

module Stackv4v6 = struct
  include Tcpip_stack_socket.V4V6

  let connect (udp : Udpv4v6_socket.t) (tcp : Tcpv4v6_socket.t) : t Lwt.t =
    Tcpip_stack_socket.V4V6.connect udp tcp
end

module Make_dispatch (DATA : sig
  type t
end) (KEYS : sig
  type t
end) (Stack : sig
  type t
end) =
struct
  type t = unit

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

  let connect ?nameservers ?timeout ?cache_size (s : S.t) (h : H.t) : D.t Lwt.t
      =
    D.connect ?nameservers ?timeout ?cache_size (s, h)
end

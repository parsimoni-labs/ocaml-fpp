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

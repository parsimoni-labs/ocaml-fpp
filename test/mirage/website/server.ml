module Unix_socket_stack = struct
  include Tcpip_stack_socket.V4V6

  let connect () : t Lwt.t = assert false
end

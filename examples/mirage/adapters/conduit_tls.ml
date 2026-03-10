(** Adapter: [Conduit_mirage.TLS(Conduit_mirage.TCP(S))] with TLS support.

    Like {!Conduit_tcp} but wraps the TCP conduit with TLS, so the server can
    accept both [`TCP port] and [`TLS (config, `TCP port)] listeners. *)

module Make (S : Tcpip.Stack.V4V6) = struct
  include Conduit_mirage.TLS (Conduit_mirage.TCP (S))

  let start s = Lwt.return s
end

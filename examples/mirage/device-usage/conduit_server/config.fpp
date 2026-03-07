passive component App {
  sync input port start: serial
  output port conduit: serial
}

instance conduit_tcp: Conduit_tcp.Make base id 0
instance app: App base id 0

topology UnixConduit {
  import SocketStack
  instance stackv4v6
  instance conduit_tcp
  @ ocaml.module Unikernel.Main
  instance app

  connections Start {
    conduit_tcp.stack -> stackv4v6.connect
    app.conduit -> conduit_tcp.start
  }
}

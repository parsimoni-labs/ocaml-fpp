passive component App {
  sync input port start: serial
  output port stack: serial
}

instance app: App base id 0

topology UnixNetwork {
  import SocketStack
  instance stackv4v6
  @ ocaml.module Unikernel.Main
  instance app

  connections Start {
    app.stack -> stackv4v6.connect
  }
}

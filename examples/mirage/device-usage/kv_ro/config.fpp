passive component App {
  sync input port start: serial
  output port kv: serial
}

instance kv_store: Kv base id 0
instance app: App base id 0

topology UnixKvRo {
  @ ocaml.module Static_t
  instance kv_store
  @ ocaml.module Unikernel.Main
  instance app

  connections Start {
    app.kv -> kv_store.connect
  }
}

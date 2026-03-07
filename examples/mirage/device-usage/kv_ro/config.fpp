module Unikernel {
  passive component Main {
    sync input port start: serial
    output port kv: serial
  }
}

instance kv_store: Kv base id 0
instance app: Unikernel.Main base id 0

topology UnixKvRo {
  @ ocaml.module Static_t
  instance kv_store
  instance app

  connections Start {
    app.kv -> kv_store.connect
  }
}

module Unikernel {
  passive component Main {
    sync input port start: serial
    output port kv: serial
  }
}

instance static_t: Kv base id 0
instance unikernel: Unikernel.Main base id 0

topology UnixKvRo {
  instance static_t
  instance unikernel

  connections Start {
    unikernel.kv -> static_t.connect
  }
}

topology Solo5KvRo {
  instance static_t
  instance unikernel

  connections Start {
    unikernel.kv -> static_t.connect
  }
}

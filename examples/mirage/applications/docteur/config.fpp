module Unikernel {
  passive component Make {
    sync input port start: serial
    output port kv: serial
  }
}

instance static_t: Kv base id 0
instance unikernel: Unikernel.Make base id 0

topology UnixDocteur {
  instance static_t
  instance unikernel

  connections Start {
    unikernel.kv -> static_t.connect
  }
}

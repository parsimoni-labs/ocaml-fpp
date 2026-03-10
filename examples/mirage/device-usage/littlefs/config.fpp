module Unikernel {
  passive component Make {
    async input port start: serial
    output port kv: serial
  }
}

instance unikernel: Unikernel.Make base id 0

topology UnixLittlefs {
  instance block(_0 = "littlefs")
  instance chamelon(programBlockSize = 16)
  instance unikernel

  connections Start {
    chamelon.block -> block.connect
    unikernel.kv -> chamelon.connect
  }
}

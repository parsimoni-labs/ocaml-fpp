module Unikernel {
  passive component Main {
    sync input port start: serial
    output port block: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixBlock {
  instance ramdisk(name = "block-test")
  instance unikernel

  connections Start {
    unikernel.block -> ramdisk.connect
  }
}

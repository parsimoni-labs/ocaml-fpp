module Unikernel {
  passive component Main {
    sync input port start: serial
    output port block: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixDiskLottery {
  instance ramdisk(name = "lottery-disk")
  instance unikernel

  connections Start {
    unikernel.block -> ramdisk.connect
  }
}

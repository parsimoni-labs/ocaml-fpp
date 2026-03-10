module Unikernel {
  passive component Main {
    async input port start: serial
    output port block: serial
    param resetAll: bool default false
    param slot: U64 default 0
    param reset: bool default false
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

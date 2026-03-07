module Unikernel {
  passive component Main {
    sync input port start: serial
    output port block: serial
  }
}

instance ramdisk: Ramdisk base id 0
instance app: Unikernel.Main base id 0

topology UnixDiskLottery {
  instance ramdisk(name = "lottery-disk")
  instance app

  connections Start {
    app.block -> ramdisk.connect
  }
}

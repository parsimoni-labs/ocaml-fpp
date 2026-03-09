module Unikernel {
  passive component Main {
    sync input port start: serial
    output port kv: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixFatKv {
  instance ramdisk(name = "disk.img")
  instance fat_kv
  instance unikernel

  connections Start {
    fat_kv.block -> ramdisk.connect
    unikernel.kv -> fat_kv.connect
  }
}

module Unikernel {
  passive component Main {
    sync input port start: serial
    output port kv: serial
  }
}

instance unikernel: Unikernel.Main base id 0

topology UnixTarKv {
  instance ramdisk(name = "data.tar")
  instance tar_kv
  instance unikernel

  connections Start {
    tar_kv.block -> ramdisk.connect
    unikernel.kv -> tar_kv.connect
  }
}

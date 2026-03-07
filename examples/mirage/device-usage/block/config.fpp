passive component App {
  sync input port start: serial
  output port block: serial
}

instance ramdisk: Block base id 0
instance app: App base id 0

topology UnixBlock {
  instance ramdisk(name = "block-test")
  @ ocaml.module Unikernel.Main
  instance app

  connections Start {
    app.block -> ramdisk.connect
  }
}

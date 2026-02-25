port P
@ ocaml.functor Srv.Make
active component Srv {
  output port kv: P
}
active component Kv { sync input port get: P }
instance kv: Kv base id 0x100
instance srv: Srv base id 0x200
topology T {
  @ ocaml.module Embedded_data
  instance kv
  instance srv
  connections W { srv.kv -> kv.get }
}

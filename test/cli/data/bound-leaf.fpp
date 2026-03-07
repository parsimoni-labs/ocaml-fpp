port P
active component Srv {
  output port kv: P
}
module Embedded {
  active component Kv { sync input port get: P }
}
instance kv: Embedded.Kv base id 0x100
instance srv: Srv base id 0x200
topology T {
  instance kv
  instance srv
  connections W { srv.kv -> kv.get }
}

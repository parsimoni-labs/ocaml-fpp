@ MirageOS type vocabulary.
@
@ External types shared by all MirageOS component and topology
@ definitions.

@ ocaml.type Cstruct.t
type Buffer

@ ocaml.type Macaddr.t
type Macaddr

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ocaml.type Ipaddr.V4.t
type Ipv4Addr

@ ── Port type definitions ────────────────────────────────
@
@ Port types model the function signatures of module values.
@ [port P(params) -> RetType] generates [val p : t -> params -> RetType].
@ Components with [@ ocaml.sig] get a [module type X_check] in the [.ml]
@ so OCaml verifies the derived sig matches the named one.

@ [val mac : t -> Macaddr.t]
port GetMac -> Macaddr

@ [val mtu : t -> int]
port GetMtu -> I16

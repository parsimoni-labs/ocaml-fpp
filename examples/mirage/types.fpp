@ MirageOS type vocabulary.
@
@ External types and port declarations shared by all MirageOS
@ component and topology definitions.

@ ── External types ─────────────────────────────────────────

@ ocaml.type Cstruct.t
type Buffer

type Macaddr

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ── Port types ─────────────────────────────────────────────
@
@ Each port type models an operation that a component provides
@ or consumes.  The generated module type maps input ports to
@ [val] declarations; output ports determine functor wiring.

port NetWrite(data: Buffer)
port NetListen(header_size: U32)
port MacAddr -> Macaddr
port Mtu -> U32
port Disconnect
port EthWrite(dst: Macaddr, payload: Buffer)
port ArpQuery(ip: Macaddr) -> Macaddr
port IpWrite(dst: string, payload: Buffer)
port IpConfig(prefix: Cidr)
port KvGet(key: string) -> string
port KvExists(key: string) -> bool
port KvList(key: string) -> string
port KvDigest(key: string) -> string


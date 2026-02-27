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

@ ── Module-type-internal types ─────────────────────────────
@
@ These map to names that are abstract within a module type sig.
@ They appear in port return types so that the generated module
@ types closely match real Mirage signatures.

@ ocaml.type key
type KvKey

@ ocaml.type (string, error) result Lwt.t
type KvGetResult

@ ocaml.type (bool option, error) result Lwt.t
type KvExistsResult

@ ocaml.type (string list, error) result Lwt.t
type KvListResult

@ ocaml.type (string, error) result Lwt.t
type KvDigestResult

@ ocaml.type unit Lwt.t
type LwtUnit

@ ── Port types ─────────────────────────────────────────────
@
@ Each port type models an operation that a component provides
@ or consumes.  The generated module type maps input ports to
@ [val] declarations; output ports determine functor wiring.

port NetWrite(data: Buffer)
port NetListen(header_size: U32)
port MacAddr -> Macaddr
port Mtu -> U32
port Disconnect -> LwtUnit
port EthWrite(dst: Macaddr, payload: Buffer)
port ArpQuery(ip: Macaddr) -> Macaddr
port IpWrite(dst: string, payload: Buffer)
port IpConfig(prefix: Cidr)
port KvGet(key: KvKey) -> KvGetResult
port KvExists(key: KvKey) -> KvExistsResult
port KvList(key: KvKey) -> KvListResult
port KvDigest(key: KvKey) -> KvDigestResult
port IpOnly -> bool
port IpCidr -> Cidr


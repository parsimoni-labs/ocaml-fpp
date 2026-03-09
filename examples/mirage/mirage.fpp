@ MirageOS device catalogue.
@
@ This file models the MirageOS device graph using native FPP constructs.
@ Each device category has an interface (OCaml module type), concrete
@ components (OCaml functors), and port types encoding connect signatures.
@
@ Layer 1 (construction): connect ports + output ports → functor wiring
@ Layer 2 (interface):    typed ports on interfaces → module type signatures
@
@ Mapping to targets:
@   port param (named)  → OCaml: ~label:v      C++: named arg
@   port param (_N)     → OCaml: positional     C++: positional
@   struct-typed param  → OCaml: expand fields  C++: expand fields
@   struct field w/ def → OCaml: optional label C++: has default
@   output port + conn  → OCaml: functor arg   C++: dep injection
@   external param      → OCaml: Cmdliner term C++: runtime config
@   instance(p = v)     → OCaml: inline value  C++: compile-time const

@ ══════════════════════════════════════════════════════
@ External types
@ ══════════════════════════════════════════════════════

@ ocaml.type Cstruct.t
type Buffer

@ ocaml.type Ipaddr.t
type IpAddr

@ ocaml.type Ipaddr.Prefix.t
type IpPrefix

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ocaml.type Ipaddr.V4.t
type Ipv4Addr

@ ocaml.type Ipaddr.V6.Prefix.t
type Cidr6

@ ocaml.type Ipaddr.V6.t
type Ipv6Addr

@ ocaml.type Macaddr.t
type Macaddr

@ ocaml.type Ptime.t
type Ptime

@ ocaml.type Optint.Int63.t
type Int63

@ ocaml.type Duration.t
type Duration

@ ocaml.type [ `host ] Domain_name.t
type DomainName

@ ocaml.type Ipaddr.Set.t
type IpAddrSet

@ ocaml.type Uri.t
type Uri

@ ══════════════════════════════════════════════════════
@ Error enums
@ ══════════════════════════════════════════════════════

@ ocaml.type Mirage_block.error
enum BlockError { Disconnected }
@ ocaml.type Mirage_block.write_error
enum BlockWriteError { Disconnected, IsReadOnly }

@ ocaml.type Mirage_net.Net.error
enum NetError { InvalidLength, Disconnected }

@ Ethernet errors (no top-level type; abstract inside S).
enum EthError { ExceedsMtu }

@ ocaml.type Arp_packet.error
enum ArpError { Timeout }

@ ocaml.type Tcpip.Ip.error
enum IpError { NoRoute, WouldFragment }

@ ICMP errors (abstract inside S).
enum IcmpError { Unreach }

@ ocaml.type Tcpip.Tcp.error
enum TcpError { Timeout, Refused }

@ ocaml.type Mirage_flow.write_error
enum FlowWriteError { Closed }

@ Flow shutdown direction (Mirage_flow).
enum FlowShutdownMode { Read, Write, ReadWrite }

@ ocaml.type Mirage_kv.error
enum KvError { NotFound, DictionaryExpected, ValueExpected }
@ ocaml.type Mirage_kv.write_error
enum KvWriteError { NotFound, NoSpace, AlreadyPresent }

@ DNS client errors (abstract inside S).
enum DnsError { Msg }

@ ══════════════════════════════════════════════════════
@ Info and config structs
@ ══════════════════════════════════════════════════════

@ ocaml.type Mirage_block.info
struct BlockInfo {
  readWrite: bool,
  sectorSize: U32,
  sizeSectors: U64
}

@ ocaml.type Mirage_net.stats
struct NetStats {
  rxBytes: U64,
  rxPkts: U32,
  txBytes: U64,
  txPkts: U32
}

@ TCP keepalive configuration (Tcp.Keepalive.t).
struct TcpKeepalive {
  after: U64,
  interval: U64,
  probes: U32
}

@ ══════════════════════════════════════════════════════
@ Protocol enums
@ ══════════════════════════════════════════════════════

@ Ethernet frame types (Ethernet.Packet.proto).
enum EthProto { ARP, IPv4, IPv6 }

@ IP protocol numbers (Tcpip.Ip.proto).
enum IpProto { TCP, UDP, ICMP }

@ ══════════════════════════════════════════════════════
@ F Prime built-in port types
@ ══════════════════════════════════════════════════════

module Fw {
  port PrmGet
  port PrmSet
}

@ ══════════════════════════════════════════════════════
@ Port types: connect signatures (Layer 1)
@ ══════════════════════════════════════════════════════
@
@ Named params → labeled (~name:value).
@ _N prefix → positional args.
@ Struct-typed params → expand as labeled fields; fields with defaults
@   become optional labels.

port SocketConnect(ipv4Only: bool, ipv6Only: bool, _0: Cidr, _1: Cidr6)

port BlockConnect(name: string)

port NetifConnect(_0: string)

port Ipv4Connect(cidr: Cidr)

@ Struct with defaults → optional labeled args.
struct Ipv6Conf { noInit: bool } default { noInit = false }
port Ipv6Connect(conf: Ipv6Conf)

port IpConnect(ipv4Only: bool, ipv6Only: bool)

port HttpServerConnect($port: U16)

port ChamelonConnect(programBlockSize: U32)

@ All fields optional (library provides defaults).
struct HappyEyeballsConf {
  aaaa_timeout: U64,
  connect_delay: U64,
  connect_timeout: U64,
  resolve_timeout: U64,
  resolve_retries: U32,
  timer_interval: U64
} default {
  aaaa_timeout = 0,
  connect_delay = 0,
  connect_timeout = 0,
  resolve_timeout = 0,
  resolve_retries = 0,
  timer_interval = 0
}
port HappyEyeballsConnect(conf: HappyEyeballsConf)

@ All fields optional (library provides defaults).
struct DnsClientConf {
  cache_size: U32,
  timeout: U64
} default {
  cache_size = 0,
  timeout = 0
}
port DnsClientConnect(conf: DnsClientConf)

@ ══════════════════════════════════════════════════════
@ Port types: device operations (Layer 2)
@ ══════════════════════════════════════════════════════
@
@ These ports model the operations each device exposes.
@ Return type = error enum for failable I/O operations.
@ Return type = data struct/type for queries.
@ No return type for fire-and-forget.

@ ── Universal operations ─────────────────────────────────
@ Mirage_device.S: every device has disconnect.

port Disconnect

@ ── Flow operations ───────────────────────────────────
@ Mirage_flow.S: reliable byte stream abstraction.

port FlowRead -> Buffer
port FlowWrite(_0: Buffer) -> FlowWriteError
port FlowClose
port FlowShutdown(mode: FlowShutdownMode) -> FlowWriteError

@ ── Block operations ──────────────────────────────────
@ Mirage_block.S: sector-addressed block device.

port BlockGetInfo -> BlockInfo
port BlockRead(offset: U64, _0: Buffer) -> BlockError
port BlockWrite(offset: U64, _0: Buffer) -> BlockWriteError

@ ── Network operations ────────────────────────────────
@ Mirage_net.S: raw network interface.

port NetWrite(size: U32, _0: Buffer) -> NetError
port NetMac -> Macaddr
port NetMtu -> U32
port NetGetStats -> NetStats
port NetResetStats
port NetListen
port NetDisconnect

@ ── Ethernet operations ───────────────────────────────
@ Ethernet.S: ethernet frame layer.

port EthWrite(dst: Macaddr, proto: EthProto, _0: Buffer) -> EthError
port EthMac -> Macaddr
port EthMtu -> U32
port EthInput(_0: Buffer)
port EthDisconnect

@ ── ARP operations ────────────────────────────────────
@ Arp.S: IPv4 address resolution.

port ArpQuery(ip: Ipv4Addr) -> Macaddr
port ArpAddIp(ip: Ipv4Addr)
port ArpRemoveIp(ip: Ipv4Addr)
port ArpRecv(_0: Buffer)

@ ── ICMP operations ───────────────────────────────────
@ Icmpv4.S: ICMPv4 messages.

port IcmpWrite(dst: Ipv4Addr, _0: Buffer) -> IcmpError
port IcmpRecv(_0: Buffer)

@ ── IP operations ─────────────────────────────────────
@ Tcpip.Ip.S: IP packet layer.

port IpWrite(dst: IpAddr, proto: IpProto, _0: Buffer) -> IpError
port IpSrc(dst: IpAddr) -> IpAddr
port IpMtu(dst: IpAddr) -> U32

@ ── UDP operations ────────────────────────────────────
@ Tcpip.Udp.S: connectionless datagram transport.

port UdpWrite(dst: IpAddr, dstPort: U16, _0: Buffer)
port UdpListen($port: U16)
port UdpUnlisten($port: U16)

@ ── TCP operations ────────────────────────────────────
@ Tcpip.Tcp.S: connection-oriented stream transport.

port TcpCreateConnection(dst: IpAddr, dstPort: U16) -> TcpError
port TcpListen($port: U16)
port TcpUnlisten($port: U16)

@ ── Stack operations ──────────────────────────────────
@ Tcpip.Stack.V4V6: composite TCP/IP stack.

port StackListen

@ ── KV operations ─────────────────────────────────────
@ Mirage_kv.RO / RW: key-value store.

port KvGet(key: string) -> KvError
port KvGetPartial(key: string, offset: I64, length: U32) -> KvError
port KvList(key: string) -> KvError
port KvExists(key: string) -> KvError
port KvSize(key: string) -> KvError
port KvLastModified(key: string) -> KvError
port KvDigest(key: string) -> KvError
port KvSet(key: string, value: string) -> KvWriteError
port KvSetPartial(key: string, offset: I64, value: string) -> KvWriteError
port KvRemove(key: string) -> KvWriteError
port KvRename(source: string, dest: string) -> KvWriteError

@ ── Clock operations ──────────────────────────────────
@ Mirage_clock.PCLOCK / MCLOCK.

port PclockNow -> I64
port MclockElapsed -> I64

@ ── Time operations ───────────────────────────────────
@ Mirage_time.S / Mirage_sleep.S.

port SleepNs(ns: I64)

@ ── DNS operations ────────────────────────────────────
@ Dns_client_mirage.S: DNS resolution.

port DnsGetaddrinfo(name: DomainName) -> DnsError
port DnsGethostbyname(name: DomainName) -> DnsError
port DnsGethostbyname6(name: DomainName) -> DnsError

@ ── Happy Eyeballs operations ─────────────────────────
@ Happy_eyeballs_mirage.S: RFC 8305 dual-stack connection.

port HeConnect(host: string, $port: U16) -> DnsError
port HeConnectIp(dst: IpAddr, $port: U16) -> DnsError

@ ── RNG operations ──────────────────────────────────────
@ Mirage_crypto_rng: cryptographic randomness.

port RngGenerate(len: U32) -> Buffer

@ ── Vnetif backend operations ───────────────────────────
@ Vnetif.BACKEND: virtual network interface backend.

port VnetifRegister -> Macaddr
port VnetifUnregister(mac: Macaddr)
port VnetifWrite(dst: Macaddr, _0: Buffer)

@ ── Conduit operations ──────────────────────────────────
@ Conduit_mirage: protocol-agnostic connection establishment.
@ Established connections use Mirage_flow.S for data transfer.

port ConduitResolve

@ ── Mimic operations ────────────────────────────────────
@ Mimic: protocol multiplexer (TCP, TLS, HTTP/2).

port MimicResolve -> DnsError

@ ── HTTP operations ─────────────────────────────────────
@ Cohttp/Paf/Http_mirage_client: HTTP request/response.

port HttpRequest(meth: string, uri: string, body: Buffer) -> Buffer
port HttpListen

@ ── Syslog operations ──────────────────────────────────
@ Syslog: remote structured logging via UDP/TCP/TLS.

port SyslogSend(msg: string)

@ ── Git operations ─────────────────────────────────────
@ Git_mirage: git smart transport (fetch/push).

port GitFetch(uri: string) -> DnsError
port GitPush(uri: string) -> DnsError

@ ── Resolver operations ────────────────────────────────
@ Resolver_mirage: hostname/service resolution.

port ResolverResolve(host: string)

@ ── Monitoring operations ──────────────────────────────
@ Monitoring: metrics reporting.

port MonitoringEnable(tags: string)

@ ══════════════════════════════════════════════════════
@ Flow abstraction
@ ══════════════════════════════════════════════════════

module Mirage_flow {
  @ Reliable byte stream (TCP connections, TLS channels).
  interface S {
    sync input port read: FlowRead
    sync input port write: FlowWrite
    sync input port close: FlowClose
    sync input port shutdown: FlowShutdown
  }
}

@ ══════════════════════════════════════════════════════
@ Infrastructure devices
@ ══════════════════════════════════════════════════════

module Mirage_sleep {
  @ Wall-clock sleep.
  interface S {
    sync input port connect: serial
    sync input port sleepNs: SleepNs
  }
}

module Mirage_ptime {
  @ POSIX clock (wall time).
  interface S {
    sync input port connect: serial
    sync input port now: PclockNow
  }
}

module Mirage_mtime {
  @ Monotonic clock (elapsed time).
  interface S {
    sync input port connect: serial
    sync input port elapsed: MclockElapsed
  }
}

module Mirage_crypto_rng {
  @ Cryptographic random number generator.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port generate: RngGenerate
  }
}

module Mirage_logs {
  @ Logging infrastructure.
  @ Minimal interface: setup installs the reporter.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
  }
}

@ ══════════════════════════════════════════════════════
@ Block devices
@ ══════════════════════════════════════════════════════

module Mirage_block {
  @ Sector-addressed block device.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port getInfo: BlockGetInfo
    sync input port read: BlockRead
    sync input port write: BlockWrite
  }
}

@ Block device backed by a file.
passive component Block {
  import Mirage_block.S
  sync input port connect: BlockConnect
}

@ In-memory block device (ramdisk).
passive component Ramdisk {
  import Mirage_block.S
  sync input port connect: BlockConnect
}

@ AES-CCM encrypted block device layer.
passive component Ccm_block {
  import Mirage_block.S
  external param key: string
  param get port prmGetOut
  param set port prmSetOut
  output port block: serial
}

@ ══════════════════════════════════════════════════════
@ Key/value stores
@ ══════════════════════════════════════════════════════

module Mirage_kv {
  @ Read-only key-value store.
  interface RO {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port $get: KvGet
    sync input port getPartial: KvGetPartial
    sync input port list: KvList
    sync input port exists: KvExists
    sync input port $size: KvSize
    sync input port lastModified: KvLastModified
    sync input port digest: KvDigest
  }

  @ Read-write key-value store (extends RO).
  interface RW {
    import Mirage_kv.RO
    sync input port $set: KvSet
    sync input port setPartial: KvSetPartial
    sync input port remove: KvRemove
    sync input port rename: KvRename
  }
}

@ Static KV store (ocaml-crunch, embedded at build time).
passive component Crunch {
  import Mirage_kv.RO
}

@ Direct filesystem access (Unix only).
passive component Direct_kv_ro {
  import Mirage_kv.RO
  sync input port connect: BlockConnect
}

@ Opaque leaf KV (e.g. crunch-generated Static_t).
passive component Kv {
  import Mirage_kv.RO
}

@ Block-backed read-only KV (generic).
passive component Block_kv {
  import Mirage_kv.RO
  output port block: serial
}

@ Tar archive read-only KV on a block device.
module Tar_mirage {
  passive component Make_KV_RO {
    import Mirage_kv.RO
    output port block: serial
  }
}

@ FAT filesystem read-only KV on a block device.
module Fat {
  passive component KV_RO {
    import Mirage_kv.RO
    output port block: serial
  }
}

@ Direct filesystem access (Unix only, read-write).
passive component Direct_kv_rw {
  import Mirage_kv.RW
  sync input port connect: BlockConnect
}

@ In-memory read-write KV store.
passive component Kv_rw_mem {
  import Mirage_kv.RW
}

@ Chamelon (littlefs) read-write filesystem on a block device.
passive component Chamelon {
  import Mirage_kv.RW
  sync input port connect: ChamelonConnect
  output port block: serial
}

@ Tar archive read-write KV on a block device.
passive component Tar_kv_rw {
  import Mirage_kv.RW
  output port block: serial
}

@ ══════════════════════════════════════════════════════
@ Network interfaces
@ ══════════════════════════════════════════════════════

module Mirage_net {
  @ Raw network interface (L2).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port write: NetWrite
    sync input port listen: NetListen
    sync input port mac: NetMac
    sync input port mtu: NetMtu
    sync input port getStats: NetGetStats
    sync input port resetStats: NetResetStats
  }
}

@ Network backend (e.g. vnetif for testing).
module Vnetif {
  interface BACKEND {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port register: VnetifRegister
    sync input port unregister: VnetifUnregister
    sync input port write: VnetifWrite
  }

  passive component Make {
    import Mirage_net.S
    output port backend: serial
  }
}

@ Host network interface.
passive component Netif {
  import Mirage_net.S
  sync input port connect: NetifConnect
}

passive component Backend {
  import Vnetif.BACKEND
}

@ ══════════════════════════════════════════════════════
@ Ethernet
@ ══════════════════════════════════════════════════════

module Ethernet {
  @ Ethernet frame layer (L2).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port write: EthWrite
    sync input port $input: EthInput
    sync input port mac: EthMac
    sync input port mtu: EthMtu
  }

  passive component Make {
    import Ethernet.S
    output port net: serial
  }
}

@ ══════════════════════════════════════════════════════
@ ARP
@ ══════════════════════════════════════════════════════

module Arp {
  @ IPv4 address resolution protocol.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port query: ArpQuery
    sync input port addIp: ArpAddIp
    sync input port removeIp: ArpRemoveIp
    sync input port recv: ArpRecv
  }

  passive component Make {
    import Arp.S
    output port eth: serial
  }
}

@ ══════════════════════════════════════════════════════
@ ICMP
@ ══════════════════════════════════════════════════════

module Icmpv4 {
  @ ICMPv4 protocol.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port write: IcmpWrite
    sync input port recv: IcmpRecv
  }

  passive component Make {
    import Icmpv4.S
    output port ip: serial
  }
}

@ ══════════════════════════════════════════════════════
@ IP / TCP / UDP
@ ══════════════════════════════════════════════════════

module Tcpip {
  module Udp {
    @ Connectionless datagram transport.
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port write: UdpWrite
      sync input port listen: UdpListen
      sync input port unlisten: UdpUnlisten
    }
  }
  module Tcp {
    @ Connection-oriented stream transport.
    @ Flow operations (read/write/close) apply to individual connections.
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port createConnection: TcpCreateConnection
      sync input port listen: TcpListen
      sync input port unlisten: TcpUnlisten
    }
  }
  module Ip {
    @ IP packet layer (v4, v6, or dual-stack).
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port write: IpWrite
      sync input port src: IpSrc
      sync input port mtu: IpMtu
    }
  }
  module Stack {
    @ Composite TCP/IP dual-stack.
    @ Provides sub-module accessors: udp, tcp, ip.
    interface V4V6 {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port listen: StackListen
    }
  }
}

module Static_ipv4 {
  passive component Make {
    import Tcpip.Ip.S
    sync input port connect: Ipv4Connect
    output port eth: serial
    output port arp: serial
  }
}

module Ipv6 {
  passive component Make {
    import Tcpip.Ip.S
    sync input port connect: Ipv6Connect
    output port net: serial
    output port eth: serial
  }
}

module Tcpip_stack_direct {
  passive component IPV4V6 {
    import Tcpip.Ip.S
    sync input port connect: IpConnect
    output port ipv4: serial
    output port ipv6: serial
  }

  passive component MakeV4V6 {
    import Tcpip.Stack.V4V6
    output port netif: serial
    output port ethernet: serial
    output port arpv4: serial
    output port ipv4v6: serial
    output port icmpv4: serial
    output port udpv4v6: serial
    output port tcpv4v6: serial
  }
}

module Udp {
  passive component Make {
    import Tcpip.Udp.S
    output port ip: serial
  }
}

module Tcp {
  module Flow {
    passive component Make {
      import Tcpip.Tcp.S
      output port ip: serial
    }
  }
}

@ ── Socket-backed transport ───────────────────────────

passive component Udpv4v6_socket {
  import Tcpip.Udp.S
  sync input port connect: SocketConnect
}

passive component Tcpv4v6_socket {
  import Tcpip.Tcp.S
  sync input port connect: SocketConnect
}

module Stackv4v6 {
  @ Socket-backed stack (udp + tcp deps).
  passive component Make {
    import Tcpip.Stack.V4V6
    output port udp: serial
    output port tcp: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Conduit / TLS
@ ══════════════════════════════════════════════════════

module Conduit_mirage {
  @ Protocol-agnostic network connection.
  @ Established connections use Mirage_flow.S for data transfer.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port resolve: ConduitResolve
    import Mirage_flow.S
  }

  passive component TLS {
    import Conduit_mirage.S
    output port conduit: serial
  }
}

module Conduit_tcp {
  passive component Make {
    import Conduit_mirage.S
    sync input port start: serial
    output port stack: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Happy Eyeballs + DNS
@ ══════════════════════════════════════════════════════

module Happy_eyeballs_mirage {
  @ RFC 8305 dual-stack connection establishment.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port heConnect: HeConnect
    sync input port heConnectIp: HeConnectIp
  }

  passive component Make {
    import Happy_eyeballs_mirage.S
    sync input port connect_device: HappyEyeballsConnect
    output port stack: serial
  }
}

module Dns_client_mirage {
  @ DNS client (recursive resolver).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port getaddrinfo: DnsGetaddrinfo
    sync input port gethostbyname: DnsGethostbyname
    sync input port gethostbyname6: DnsGethostbyname6
  }
}

module Dns_resolver {
  @ connect takes (stack * happy_eyeballs) tuple; adapter unpacks via start.
  passive component Make {
    import Dns_client_mirage.S
    sync input port start: DnsClientConnect
    output port stack: serial
    output port happy_eyeballs: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Mimic (protocol-agnostic connection layer)
@ ══════════════════════════════════════════════════════

module Mimic {
  @ Protocol multiplexer (TCP, TLS, HTTP/2).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port resolve: MimicResolve
  }

  @ mimic_happy_eyeballs : stackv4v6 -> happy_eyeballs -> dns_client -> mimic
  passive component Make {
    import Mimic.S
    output port stack: serial
    output port happy_eyeballs: serial
    output port dns: serial
  }
}

@ ══════════════════════════════════════════════════════
@ HTTP
@ ══════════════════════════════════════════════════════

module Cohttp_mirage {
  module Server {
    @ HTTP server (Cohttp over Conduit).
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port listen: HttpListen
    }

    passive component Make {
      import Cohttp_mirage.Server.S
      output port conduit: serial
    }
  }

  module Client {
    @ HTTP client (Cohttp over Conduit).
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port $request: HttpRequest
    }

    @ cohttp_client : resolver -> conduit -> http_client
    passive component Make {
      import Cohttp_mirage.Client.S
      output port resolver: serial
      output port conduit: serial
    }
  }
}

module Paf_mirage {
  @ HTTP server (h2/httpaf over TCP).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port listen: HttpListen
  }

  @ paf_server : ~port:int runtime_arg -> tcpv4v6 -> http_server
  passive component Server {
    import Paf_mirage.S
    sync input port connect: HttpServerConnect
    output port tcp: serial
  }
}

module Http_mirage_client {
  @ HTTP client (ALPN-negotiated, supports h2 and HTTP/1.1).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port $request: HttpRequest
  }

  @ paf_client : tcpv4v6 -> mimic -> alpn_client
  passive component Make {
    import Http_mirage_client.S
    output port tcp: serial
    output port mimic: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Syslog
@ ══════════════════════════════════════════════════════

module Syslog {
  @ Remote structured logging.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port send: SyslogSend
  }

  @ syslog_udp : stackv4v6 -> syslog
  passive component Udp {
    import Syslog.S
    output port stack: serial
  }

  @ syslog_tcp : stackv4v6 -> syslog
  passive component Tcp {
    import Syslog.S
    output port stack: serial
  }

  @ syslog_tls : stackv4v6 -> kv_ro -> syslog
  passive component Tls {
    import Syslog.S
    output port stack: serial
    output port certs: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Git client
@ ══════════════════════════════════════════════════════

module Git_mirage {
  @ Git smart transport (fetch/push over TCP/SSH/HTTP).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port fetch: GitFetch
    sync input port push: GitPush
  }

  @ git_tcp : tcpv4v6 -> mimic -> git_client
  passive component Tcp {
    import Git_mirage.S
    output port tcp: serial
    output port mimic: serial
  }

  @ git_ssh : tcpv4v6 -> mimic -> git_client
  @ (authenticator, key, password are runtime secrets)
  passive component Ssh {
    import Git_mirage.S
    external param authenticator: string default ""
    external param key: string default ""
    external param password: string default ""
    param get port prmGetOut
    param set port prmSetOut
    output port tcp: serial
    output port mimic: serial
  }

  @ git_http : tcpv4v6 -> mimic -> git_client
  passive component Http {
    import Git_mirage.S
    external param authenticator: string default ""
    param get port prmGetOut
    param set port prmSetOut
    output port tcp: serial
    output port mimic: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Resolver (legacy conduit-based)
@ ══════════════════════════════════════════════════════

module Resolver_mirage {
  @ Hostname/service resolution (legacy conduit-based).
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port resolve: ResolverResolve
  }

  @ resolver_dns : ?nameservers -> stackv4v6 -> resolver
  passive component Make {
    import Resolver_mirage.S
    output port stack: serial
  }
}

@ Unix system resolver (no deps).
passive component Resolver_unix_system {
  import Resolver_mirage.S
}

@ ══════════════════════════════════════════════════════
@ DHCP-based IPv4
@ ══════════════════════════════════════════════════════

@ ipv4_of_dhcp : network -> ethernet -> arpv4 -> ipv4
module Dhcp_ipv4 {
  passive component Make {
    import Tcpip.Ip.S
    output port net: serial
    output port eth: serial
    output port arp: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Monitoring
@ ══════════════════════════════════════════════════════

module Monitoring {
  @ Metrics reporting.
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port enable: MonitoringEnable
  }

  @ monitoring : stackv4v6 -> job
  passive component Make {
    import Monitoring.S
    output port stack: serial
  }
}

@ ══════════════════════════════════════════════════════
@ Device instances
@ ══════════════════════════════════════════════════════

instance backend: Backend base id 0
instance net: Vnetif.Make base id 0
instance netif: Netif base id 0
instance udpv4v6_socket: Udpv4v6_socket base id 0
instance tcpv4v6_socket: Tcpv4v6_socket base id 0
instance stackv4v6: Stackv4v6.Make base id 0
instance ethernet: Ethernet.Make base id 0
instance arp: Arp.Make base id 0
instance ipv4: Static_ipv4.Make base id 0
instance ipv6: Ipv6.Make base id 0
instance ip: Tcpip_stack_direct.IPV4V6 base id 0
instance icmp: Icmpv4.Make base id 0
instance udp: Udp.Make base id 0
instance tcp: Tcp.Flow.Make base id 0
instance stack: Tcpip_stack_direct.MakeV4V6 base id 0
instance ramdisk: Ramdisk base id 0
instance data: Kv base id 0
instance certs: Kv base id 0
instance htdocs_data: Kv base id 0
instance tls_data: Kv base id 0
instance data_block: Block base id 0
instance certs_block: Block base id 0
instance tar_data: Tar_mirage.Make_KV_RO base id 0
instance tar_certs: Tar_mirage.Make_KV_RO base id 0
instance fat_data: Fat.KV_RO base id 0
instance fat_certs: Fat.KV_RO base id 0
instance conduit_tcp: Conduit_tcp.Make base id 0
instance happy_eyeballs_mirage: Happy_eyeballs_mirage.Make base id 0
instance dns_client: Dns_resolver.Make base id 0

@ ══════════════════════════════════════════════════════
@ Sub-topologies
@ ══════════════════════════════════════════════════════

topology TcpipStack {
  instance backend
  instance net
  instance ethernet
  instance arp
  instance ipv4(cidr = "10.0.0.2/24")
  instance ipv6
  instance ip(ipv4Only = false, ipv6Only = false)
  instance icmp
  instance udp
  instance tcp
  instance stack

  connections Connect {
    net.backend -> backend.connect
    ethernet.net -> net.connect
    arp.eth -> ethernet.connect
    ipv4.eth -> ethernet.connect
    ipv4.arp -> arp.connect
    ipv6.net -> net.connect
    ipv6.eth -> ethernet.connect
    ip.ipv4 -> ipv4.connect
    ip.ipv6 -> ipv6.connect
    icmp.ip -> ipv4.connect
    udp.ip -> ip.connect
    tcp.ip -> ip.connect
    stack.netif -> net.connect
    stack.ethernet -> ethernet.connect
    stack.arpv4 -> arp.connect
    stack.ipv4v6 -> ip.connect
    stack.icmpv4 -> icmp.connect
    stack.udpv4v6 -> udp.connect
    stack.tcpv4v6 -> tcp.connect
  }
}

topology SocketStack {
  instance udpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
  instance tcpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
  instance stackv4v6

  connections Connect {
    stackv4v6.udp -> udpv4v6_socket.connect
    stackv4v6.tcp -> tcpv4v6_socket.connect
  }
}

topology DnsStack {
  instance happy_eyeballs_mirage
  instance dns_client

  connections Start {
    dns_client.happy_eyeballs -> happy_eyeballs_mirage.connect_device
  }
}

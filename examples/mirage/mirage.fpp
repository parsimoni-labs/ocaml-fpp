@ MirageOS device catalogue.
@ See README.md for the two-layer design and translation conventions.

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

enum EthError { ExceedsMtu }

@ ocaml.type Arp_packet.error
enum ArpError { Timeout }

@ ocaml.type Tcpip.Ip.error
enum IpError { NoRoute, WouldFragment }

enum IcmpError { Unreach }

@ ocaml.type Tcpip.Tcp.error
enum TcpError { Timeout, Refused }

@ ocaml.type Mirage_flow.write_error
enum FlowWriteError { Closed }

enum FlowShutdownMode { Read, Write, ReadWrite }

@ ocaml.type Mirage_kv.error
enum KvError { NotFound, DictionaryExpected, ValueExpected }
@ ocaml.type Mirage_kv.write_error
enum KvWriteError { NotFound, NoSpace, AlreadyPresent }

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

struct TcpKeepalive {
  after: U64,
  interval: U64,
  probes: U32
}

@ ══════════════════════════════════════════════════════
@ Protocol enums
@ ══════════════════════════════════════════════════════

enum EthProto { ARP, IPv4, IPv6 }
enum IpProto { TCP, UDP, ICMP }

@ ══════════════════════════════════════════════════════
@ F Prime built-in port types
@ ══════════════════════════════════════════════════════

@ Required by components that declare param get/set ports (e.g. Ccm_block,
@ Git_mirage.Ssh). The checker validates Fw.PrmGet and Fw.PrmSet exist.
module Fw {
  port PrmGet
  port PrmSet
}

@ ══════════════════════════════════════════════════════
@ Port types: connect signatures (Layer 1)
@ ══════════════════════════════════════════════════════

port SocketConnect(ipv4Only: bool, ipv6Only: bool, _0: Cidr, _1: Cidr6)

port BlockConnect(name: string)

port NetifConnect(_0: string)

port Ipv4Connect(cidr: Cidr)

struct Ipv6Conf { noInit: bool } default { noInit = false }
port Ipv6Connect(conf: Ipv6Conf)

port IpConnect(ipv4Only: bool, ipv6Only: bool)

port HttpServerConnect($port: U16)

port ChamelonConnect(programBlockSize: U32)

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

@ ── Universal ────────────────────────────────────────────

port Disconnect

@ ── Flow ──────────────────────────────────────────────

port FlowRead -> Buffer
port FlowWrite(_0: Buffer) -> FlowWriteError
port FlowClose
port FlowShutdown(mode: FlowShutdownMode) -> FlowWriteError

@ ── Block ─────────────────────────────────────────────

port BlockGetInfo -> BlockInfo
port BlockRead(offset: U64, _0: Buffer) -> BlockError
port BlockWrite(offset: U64, _0: Buffer) -> BlockWriteError

@ ── Network ───────────────────────────────────────────

port NetWrite(size: U32, _0: Buffer) -> NetError
port NetMac -> Macaddr
port NetMtu -> U32
port NetGetStats -> NetStats
port NetResetStats
port NetListen
port NetDisconnect

@ ── Ethernet ──────────────────────────────────────────

port EthWrite(dst: Macaddr, proto: EthProto, _0: Buffer) -> EthError
port EthMac -> Macaddr
port EthMtu -> U32
port EthInput(_0: Buffer)
port EthDisconnect

@ ── ARP ───────────────────────────────────────────────

port ArpQuery(ip: Ipv4Addr) -> Macaddr
port ArpAddIp(ip: Ipv4Addr)
port ArpRemoveIp(ip: Ipv4Addr)
port ArpRecv(_0: Buffer)

@ ── ICMP ──────────────────────────────────────────────

port IcmpWrite(dst: Ipv4Addr, _0: Buffer) -> IcmpError
port IcmpRecv(_0: Buffer)

@ ── IP ────────────────────────────────────────────────

port IpInput(src: IpAddr, dst: IpAddr, _0: Buffer)
port IpWrite(dst: IpAddr, proto: IpProto, _0: Buffer) -> IpError
port IpSrc(dst: IpAddr) -> IpAddr
port IpMtu(dst: IpAddr) -> U32

@ ── UDP ───────────────────────────────────────────────

port UdpWrite(dst: IpAddr, dstPort: U16, _0: Buffer)
port UdpListen($port: U16)
port UdpUnlisten($port: U16)

@ ── TCP ───────────────────────────────────────────────

port TcpCreateConnection(dst: IpAddr, dstPort: U16) -> TcpError
port TcpListen($port: U16)
port TcpUnlisten($port: U16)

@ ── Stack ─────────────────────────────────────────────

port StackListen

@ ── KV ────────────────────────────────────────────────

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

@ ── Clock ─────────────────────────────────────────────

port PclockNow -> I64
port MclockElapsed -> I64

@ ── Time ──────────────────────────────────────────────

port SleepNs(ns: I64)

@ ── DNS ───────────────────────────────────────────────

port DnsGetaddrinfo(name: DomainName) -> DnsError
port DnsGethostbyname(name: DomainName) -> DnsError
port DnsGethostbyname6(name: DomainName) -> DnsError

@ ── Happy Eyeballs ────────────────────────────────────

port HeConnect(host: string, $port: U16) -> DnsError
port HeConnectIp(dst: IpAddr, $port: U16) -> DnsError

@ ── RNG ───────────────────────────────────────────────

port RngGenerate(len: U32) -> Buffer

@ ── Vnetif backend ────────────────────────────────────

port VnetifRegister -> Macaddr
port VnetifUnregister(mac: Macaddr)
port VnetifWrite(dst: Macaddr, _0: Buffer)

@ ── Conduit ───────────────────────────────────────────

port ConduitResolve

@ ── Mimic ─────────────────────────────────────────────

port MimicResolve -> DnsError

@ ── HTTP ──────────────────────────────────────────────

port HttpRequest(meth: string, uri: string, body: Buffer) -> Buffer
port HttpListen

@ ── Syslog ────────────────────────────────────────────

port SyslogSend(msg: string)

@ ── Git ───────────────────────────────────────────────

port GitFetch(uri: string) -> DnsError
port GitPush(uri: string) -> DnsError

@ ── Resolver ──────────────────────────────────────────

port ResolverResolve(host: string)

@ ── Monitoring ────────────────────────────────────────

port MonitoringEnable(tags: string)

@ ══════════════════════════════════════════════════════
@ Flow abstraction
@ ══════════════════════════════════════════════════════

module Mirage_flow {
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
  interface S {
    sync input port connect: serial
    sync input port sleepNs: SleepNs
  }
}

module Mirage_ptime {
  interface S {
    sync input port connect: serial
    sync input port now: PclockNow
  }
}

module Mirage_mtime {
  interface S {
    sync input port connect: serial
    sync input port elapsed: MclockElapsed
  }
}

module Mirage_crypto_rng {
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port generate: RngGenerate
  }
}

module Mirage_logs {
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
  }
}

@ ══════════════════════════════════════════════════════
@ Block devices
@ ══════════════════════════════════════════════════════

module Mirage_block {
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port getInfo: BlockGetInfo
    sync input port read: BlockRead
    sync input port write: BlockWrite
  }
}

passive component Block {
  import Mirage_block.S
  sync input port connect: BlockConnect
}

passive component Ramdisk {
  import Mirage_block.S
  sync input port connect: BlockConnect
}

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

  interface RW {
    import Mirage_kv.RO
    sync input port $set: KvSet
    sync input port setPartial: KvSetPartial
    sync input port remove: KvRemove
    sync input port rename: KvRename
  }
}

passive component Crunch {
  import Mirage_kv.RO
}

passive component Direct_kv_ro {
  import Mirage_kv.RO
  sync input port connect: BlockConnect
}

passive component Kv {
  import Mirage_kv.RO
}

passive component Block_kv {
  import Mirage_kv.RO
  output port block: serial
}

module Tar_mirage {
  passive component Make_KV_RO {
    import Mirage_kv.RO
    output port block: serial
  }
}

module Fat {
  passive component KV_RO {
    import Mirage_kv.RO
    output port block: serial
  }
}

passive component Direct_kv_rw {
  import Mirage_kv.RW
  sync input port connect: BlockConnect
}

passive component Kv_rw_mem {
  import Mirage_kv.RW
}

passive component Chamelon {
  import Mirage_kv.RW
  sync input port connect: ChamelonConnect
  output port block: serial
}

passive component Tar_kv_rw {
  import Mirage_kv.RW
  output port block: serial
}

@ ══════════════════════════════════════════════════════
@ Network interfaces
@ ══════════════════════════════════════════════════════

module Mirage_net {
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
    output port on_frame: serial
  }
}

passive component Netif {
  import Mirage_net.S
  sync input port connect: NetifConnect
  output port on_frame: serial
}

passive component Backend {
  import Vnetif.BACKEND
}

@ ══════════════════════════════════════════════════════
@ Ethernet
@ ══════════════════════════════════════════════════════

module Ethernet {
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
    output port on_arp: serial
    output port on_ipv4: serial
    output port on_ipv6: serial
  }
}

@ ══════════════════════════════════════════════════════
@ ARP
@ ══════════════════════════════════════════════════════

module Arp {
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
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port write: UdpWrite
      sync input port listen: UdpListen
      sync input port unlisten: UdpUnlisten
    }
  }
  module Tcp {
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port createConnection: TcpCreateConnection
      sync input port listen: TcpListen
      sync input port unlisten: TcpUnlisten
    }
  }
  module Ip {
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port $input: IpInput
      sync input port write: IpWrite
      sync input port src: IpSrc
      sync input port mtu: IpMtu
    }
  }
  module Stack {
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
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port getaddrinfo: DnsGetaddrinfo
    sync input port gethostbyname: DnsGethostbyname
    sync input port gethostbyname6: DnsGethostbyname6
  }
}

module Dns_resolver {
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
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port resolve: MimicResolve
  }

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
    interface S {
      sync input port connect: serial
      sync input port disconnect: Disconnect
      sync input port $request: HttpRequest
    }

    passive component Make {
      import Cohttp_mirage.Client.S
      output port resolver: serial
      output port conduit: serial
    }
  }
}

module Paf_mirage {
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port listen: HttpListen
  }

  passive component Server {
    import Paf_mirage.S
    sync input port connect: HttpServerConnect
    output port tcp: serial
  }
}

module Http_mirage_client {
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port $request: HttpRequest
  }

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
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port send: SyslogSend
  }

  passive component Udp {
    import Syslog.S
    output port stack: serial
  }

  passive component Tcp {
    import Syslog.S
    output port stack: serial
  }

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
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port fetch: GitFetch
    sync input port push: GitPush
  }

  passive component Tcp {
    import Git_mirage.S
    output port tcp: serial
    output port mimic: serial
  }

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
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port resolve: ResolverResolve
  }

  passive component Make {
    import Resolver_mirage.S
    output port stack: serial
  }
}

passive component Resolver_unix_system {
  import Resolver_mirage.S
}

@ ══════════════════════════════════════════════════════
@ DHCP-based IPv4
@ ══════════════════════════════════════════════════════

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
  interface S {
    sync input port connect: serial
    sync input port disconnect: Disconnect
    sync input port enable: MonitoringEnable
  }

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
instance block: Block base id 0
instance ramdisk: Ramdisk base id 0
instance chamelon: Chamelon base id 0
instance tar_kv: Tar_mirage.Make_KV_RO base id 0
instance fat_kv: Fat.KV_RO base id 0
instance conduit_tcp: Conduit_tcp.Make base id 0
instance conduit_tls: Conduit_mirage.TLS base id 0
instance resolver_unix: Resolver_unix_system base id 0
instance cohttp_server: Cohttp_mirage.Server.Make base id 0
instance cohttp_client: Cohttp_mirage.Client.Make base id 0
instance paf_server: Paf_mirage.Server base id 0
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

  connections Dataflow {
    net.on_frame -> ethernet.$input
    ethernet.on_arp -> arp.recv
    ethernet.on_ipv4 -> ipv4.$input
    ethernet.on_ipv6 -> ipv6.$input
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

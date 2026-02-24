@ MirageOS device catalogue and topologies.
@
@ Active components have runtime state (type t, connect).
@ Passive components are module-only (functor applications only).

@ ── External types ─────────────────────────────────────────

@ ocaml.type Cstruct.t
type Buffer

type Macaddr

@ ocaml.type Ipaddr.V4.Prefix.t
type Cidr

@ ── Port types ─────────────────────────────────────────────

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
port TlsFlow(payload: Buffer)
port HttpConn(uri: string)

@ ── Leaf devices ────────────────────────────────────────────

active component Net {
  sync input port disconnect: Disconnect
  sync input port write: NetWrite
  sync input port listen: NetListen
  sync input port mac: MacAddr
  sync input port mtu: Mtu
}

active component Kv {
  sync input port disconnect: Disconnect
  sync input port get: KvGet
  sync input port exists: KvExists
  sync input port list: KvList
  sync input port digest: KvDigest
}

@ ── Protocol layers ─────────────────────────────────────────

active component Ethernet {
  output port net_write: NetWrite
  sync input port write: EthWrite
}

active component Arp {
  output port eth_write: EthWrite
  sync input port query: ArpQuery
}

@ ocaml.functor Static_ipv4.Make
active component Ipv4 {
  output port eth_write: EthWrite
  output port arp_query: ArpQuery
  sync input port write: IpWrite
  @ ocaml.param
  sync input port cidr: IpConfig
}

@ ocaml.functor Icmpv4.Make
active component Icmp {
  output port ip_write: IpWrite
}

active component Udp {
  output port ip_write: IpWrite
}

@ ocaml.functor Tcp.Flow.Make
active component Tcp {
  output port ip_write: IpWrite
  sync input port write: IpWrite
}

@ ── Module-only wrappers ──────────────────────────────────

passive component Tls_mirage {
  output port tcp: IpWrite
  sync input port flow: TlsFlow
}

@ ocaml.functor Cohttp_mirage.Server.Flow
passive component Https_srv {
  output port tls: TlsFlow
  sync input port serve: HttpConn
}

@ ocaml.functor Cohttp_mirage.Server.Flow
passive component Http_srv {
  output port tcp: IpWrite
  sync input port serve: HttpConn
}

@ ── Application ───────────────────────────────────────────

@ ocaml.functor Server.HTTPS
active component Server {
  output port data_read: KvGet
  output port certs_read: KvGet
  output port http: HttpConn
}

@ ── Instances ───────────────────────────────────────────────

instance net: Net base id 0x100
instance eth: Ethernet base id 0x200
instance arp: Arp base id 0x300
instance ipv4: Ipv4 base id 0x400
instance icmp: Icmp base id 0x500
instance udp: Udp base id 0x600
instance tcp: Tcp base id 0x700
instance data: Kv base id 0x800
instance certs: Kv base id 0x900
instance tls: Tls_mirage base id 0xA00
instance https_srv: Https_srv base id 0xA10
instance http_srv: Http_srv base id 0xA20
instance server: Server base id 0xB00

@ ── Topologies ──────────────────────────────────────────────

topology TcpipStack {
  instance net
  instance eth
  instance arp
  instance ipv4
  instance icmp
  instance udp
  instance tcp

  connections Wiring {
    eth.net_write -> net.write
    arp.eth_write -> eth.write
    ipv4.eth_write -> eth.write
    ipv4.arp_query -> arp.query
    icmp.ip_write -> ipv4.write
    udp.ip_write -> ipv4.write
    tcp.ip_write -> ipv4.write
  }
}

topology StaticWebsite {
  instance net
  instance eth
  instance arp
  instance ipv4
  instance tcp
  instance data
  instance certs
  instance tls
  instance https_srv
  instance http_srv
  instance server

  connections Wiring {
    eth.net_write -> net.write
    arp.eth_write -> eth.write
    ipv4.eth_write -> eth.write
    ipv4.arp_query -> arp.query
    tcp.ip_write -> ipv4.write
    tls.tcp -> tcp.write
    https_srv.tls -> tls.flow
    http_srv.tcp -> tcp.write
    server.data_read -> data.get
    server.certs_read -> certs.get
    server.http -> https_srv.serve
  }
}

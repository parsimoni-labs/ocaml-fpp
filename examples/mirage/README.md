# MirageOS Example

This example models the MirageOS device and unikernel composition layer
in FPP.  The FPP topology graph drives functor application order and
`connect` call wiring — the same job `functoria` does today, but
expressed as a typed connection graph instead of a combinator DSL.

## File layout

| File | Role |
|---|---|
| `mirage.fpp` | Device catalogue + topologies |
| `mirage.ml` | Generated module type aliases (`ofpp to-ml --types`) |
| `main.ml` | Generated topology + entry point (`ofpp to-ml --topologies`) |
| `server.ml` | User code: HTTPS dispatch, `Unix_socket_stack` wrapper |
| `htdocs/`, `tls/` | Static assets (crunched into `Htdocs_data`, `Tls_data`) |

## Component correspondence

Each FPP `component` maps to one MirageOS functor (or leaf module).
Output ports declare functor dependencies; the connection graph
determines application order.

| FPP component | OCaml module | Functor | Package |
|---|---|---|---|
| `Backend` | *(leaf parameter)* | — | `mirage-vnetif` |
| `SocketStack` | `Tcpip_stack_socket.V4V6` | — | `tcpip.stack-socket` |
| `Vnetif` | `Vnetif.Make` | `Make(Backend)` | `mirage-vnetif` |
| `Ethernet` | `Ethernet.Make` | `Make(Net)` | `ethernet` |
| `Arp` | `Arp.Make` | `Make(Ethernet)` | `arp.mirage` |
| `Static_ipv4` | `Static_ipv4.Make` | `Make(Ethernet, Arp)` | `tcpip.ipv4` |
| `Ipv6` | `Ipv6.Make` | `Make(Net, Ethernet)` | `tcpip.ipv6` |
| `Ip` | `Tcpip_stack_direct.IPV4V6` | `IPV4V6(Ipv4, Ipv6)` | `tcpip.stack-direct` |
| `Icmpv4` | `Icmpv4.Make` | `Make(Ipv4)` | `tcpip.icmpv4` |
| `Udp` | `Udp.Make` | `Make(IP)` | `tcpip.udp` |
| `Tcp.Flow` | `Tcp.Flow.Make` | `Make(IP)` | `tcpip.tcp` |
| `TcpipStack` | `Tcpip_stack_direct.MakeV4V6` | `MakeV4V6(Net,Eth,Arp,IP,Icmp,Udp,Tcp)` | `tcpip.stack-direct` |
| `Conduit_tcp` | `Conduit_mirage.TCP` | `TCP(Stack)` | `conduit-mirage` |
| `Conduit` | `Conduit_mirage.TLS` | `TLS(Conduit_tcp)` | `conduit-mirage` |
| `Cohttp_mirage.Server` | `Cohttp_mirage.Server.Make` | `Make(Conduit)` | `cohttp-mirage` |
| `Happy_eyeballs_mirage` | `Happy_eyeballs_mirage.Make` | `Make(Stack)` | `happy-eyeballs-mirage` |
| `Dns_client_mirage` | `Dns_client_mirage.Make` | `Make(Stack)(HE)` | `dns-client-mirage` |
| `Kv` | *(leaf parameter)* | — | `mirage-kv` |
| `Block` | *(leaf parameter)* | — | `mirage-block` |
| `Tar_kv_ro` | `Tar_mirage.Make_KV_RO` | `Make_KV_RO(Block)` | `tar-mirage` |
| `Fat_kv_ro` | `Fat.KV_RO` | `KV_RO(Block)` | `fat-filesystem` |

## Annotation correspondence

| FPP annotation | Effect | Example |
|---|---|---|
| `@ ocaml.functor X.Y` | Override default functor path | `@ ocaml.functor Tcpip_stack_direct.IPV4V6` on `Ip` |
| `@ ocaml.module M` | Bind leaf to concrete module | `@ ocaml.module Mirage_kv_mem` on `instance data` |
| `@ ocaml.type T` | Map abstract FPP type to OCaml type | `@ ocaml.type Cstruct.t` on `type Buffer` |

Default functor: `ComponentName.Make` (e.g. `Ethernet` → `Ethernet.Make`).
Only needs annotation when the OCaml path differs (e.g. `Ip` →
`Tcpip_stack_direct.IPV4V6`).

## Port correspondence

FPP ports model the operations a component provides or consumes.
Input ports become `val` declarations in the generated module type;
output ports determine functor wiring.

| FPP port | Generated OCaml |
|---|---|
| `sync input port write: NetWrite` | `val write : t -> Cstruct.t -> unit` |
| `sync input port cidr: IpConfig` | `val cidr : t -> Ipaddr.V4.Prefix.t -> unit` |
| `sync input port provide: Dep` | `val provide : t -> unit` |
| `output port eth_write: EthWrite` | Functor dependency (not a val) |

## Topology composition

Sub-topologies are shared via `import`:

```
topology StaticWebsite {
  import TcpipStack        -- protocol stack
  import HttpStack          -- conduit + cohttp
  instance data             -- leaf: KV for htdocs
  instance certs            -- leaf: KV for TLS certs
  connections Connect {
    conduit_tcp.stack -> stack.provide
  }
}
```

The parent topology wires cross-boundary connections (here: plugging
the TCP/IP stack into conduit).

## Fully-bound vs parameterised topologies

| Topology | Leaves | Mode |
|---|---|---|
| `TcpipStack` | `backend` (unbound) | Functor with `BACKEND` parameter |
| `StaticWebsite` | `backend`, `data`, `certs` (unbound) | Functor with 3 parameters |
| `UnixWebsite` | all bound via `@ ocaml.module` | Struct (no functor parameters) |
| `UnixTestWebsite` | all bound (uses `Mirage_kv_mem`) | Struct (no functor parameters) |

Fully-bound topologies generate a `let () = Lwt_main.run ...` entry
point when passed to `ofpp to-ml --topologies`.

## Generating code

```sh
# Module type aliases only
ofpp to-ml --types mirage.fpp > mirage.ml

# Single topology with entry point
ofpp to-ml --topologies UnixWebsite mirage.fpp > main.ml

# Multiple topologies
ofpp to-ml --topologies UnixWebsite,UnixTestWebsite mirage.fpp > main.ml
```

## Known limitations

- **`connect` signature assumption.** The generated code assumes each
  active component has `connect : deps -> t Lwt.t`.  Libraries with
  non-standard lifecycle functions (e.g. `Happy_eyeballs_mirage`
  uses `connect_device`, `Dns_client_mirage.connect` takes a tuple)
  require a user-provided wrapper component.

- **Generated module types are narrow.** Port-based module types use
  simplified signatures (`string` instead of `Mirage_kv.key`,
  no `Lwt.t` return types).  Fully-bound topologies bypass this
  because bound modules satisfy real functor constraints directly.

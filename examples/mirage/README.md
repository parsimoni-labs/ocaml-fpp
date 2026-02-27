# MirageOS Example

This example models the MirageOS device and unikernel composition layer
in FPP.  The FPP topology graph drives functor application order and
`connect` call wiring — the same job `functoria` does today, but
expressed as a typed connection graph instead of a combinator DSL.

## Two-layer design

FPP models MirageOS in two independent layers:

### Layer 1: Device construction (current)

What FPP models today:

- **Dependency graph** — which devices plug into which constructors
  (output ports → `sync input port connect`)
- **Functor application** — `module Arp = Arp.Make(Ethernet)` from the
  connection graph
- **Assembly order** — topological sort determines `connect` call
  sequence via lazy bindings

What is **out of scope** at layer 1:

- What functions a device exposes (`write`, `get`, `listen`, etc.)
- Module type signatures
- How end-users call the device after construction

Every component declares `sync input port connect` as its universal
connection target.  Output ports name constructor dependencies.  The
target port name is a validation gate — codegen ignores it and derives
`connect` call arguments from the source-side output port declaration
order.

### Layer 2: Device interface (future, for interop)

When C++ and OCaml MirageOS components share the same memory address
space, FPP must be the source of truth for the interface contract —
what operations flow across component boundaries.

Layer 2 **adds** to layer 1:

- Typed input ports (e.g. `sync input port write: NetWrite`)
- Port type declarations (e.g. `port NetWrite(data: Buffer)`)
- Abstract type declarations (e.g. `type Error`)
- Generated module type signatures (e.g. `module type BLOCK = sig ... end`)
- `--types` CLI flag to emit module types separately

Layer 2 builds on top of layer 1.  You can do construction without
interface, but not the reverse.  The construction graph stays the same
when interfaces are added.

## File layout

FPP definitions are split across themed files:

| File | Role |
|---|---|
| `types.fpp` | External type mappings |
| `devices.fpp` | Component definitions and instance declarations |
| `stacks.fpp` | Infrastructure sub-topologies (`TcpipStack`, `SocketStack`, `DnsStack`) |
| `websites.fpp` | Composed web-server topologies (Unix, Xen/Solo5 variants) |
| `server.ml` | User code: HTTPS dispatch, `Unix_socket_stack` wrapper |
| `htdocs/`, `tls/` | Static assets (crunched into `Htdocs_data`, `Tls_data`) |

Generated files (via `dune build`):

| File | Rule |
|---|---|
| `mirage.fpp` | Full namespace (concatenation of all themed `.fpp` files) |
| `main.ml` | Topology + entry point (`ofpp to-ml --topologies UnixWebsite`) |

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
| `Server` | `Server.HTTPS` | `HTTPS(Data)(Certs)(Stack)` | *(user code)* |
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

## Topology composition

Sub-topologies are shared via `import`:

```
topology StaticWebsite {
  import TcpipStack        -- protocol stack
  instance data             -- leaf: KV for htdocs
  instance certs            -- leaf: KV for TLS certs
  instance server
  connections Connect {
    server.data -> data.connect
    server.certs -> certs.connect
    server.stack -> stack.connect
  }
}
```

The parent topology wires cross-boundary connections (here: plugging
the TCP/IP stack and KV stores into the server).

## Fully-bound vs parameterised topologies

| Topology | Leaves | Mode |
|---|---|---|
| `TcpipStack` | `backend` (unbound) | Functor with `BACKEND` parameter |
| `StaticWebsite` | `backend`, `data`, `certs` (unbound) | Functor with 3 parameters |
| `UnixWebsite` | all bound via `@ ocaml.module` | Flat (no functor parameters) |

Fully-bound topologies generate a `let () = Lwt_main.run ...` entry
point when passed to `ofpp to-ml --topologies`.

## Generating code

```sh
# Single topology with entry point
ofpp to-ml --topologies UnixWebsite types.fpp devices.fpp stacks.fpp websites.fpp

# Multiple topologies
ofpp to-ml --topologies UnixWebsite,UnixTestWebsite types.fpp devices.fpp stacks.fpp websites.fpp
```

## Key design differences from Mirage/Functoria

| Aspect | Mirage | ofpp |
|---|---|---|
| Input format | OCaml combinator DSL (`config.ml`) | FPP connection graph |
| Module naming | Mangled (`Tcpip_stack_socket_v4v6__13`) | Clean (`Socket_stack`) |
| Async style | `Lwt.Infix` (`>>=`) | `Lwt.Syntax` (`let*`) |
| Runtime args | Generated key registration | Not modelled (user code) |
| Unikernel functor | Included in `main.ml` | Left to user |
| Socket stack | Models UDP/TCP sub-layers | Opaque module alias |
| Boilerplate | ~90 lines per example | ~10-20 lines per example |

## Known limitations

- **`connect` signature assumption.** The generated code assumes each
  active component has `connect : deps -> t Lwt.t`.  Libraries with
  non-standard lifecycle functions (e.g. `Happy_eyeballs_mirage`
  uses `connect_device`, `Dns_client_mirage.connect` takes a tuple)
  require a user-provided wrapper component.

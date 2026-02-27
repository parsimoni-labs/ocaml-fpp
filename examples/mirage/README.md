# MirageOS Example

This example models the MirageOS device and unikernel composition layer
in FPP.  The FPP topology graph drives functor application order and
`connect` call wiring — the same job `functoria` does today, but
expressed as a typed connection graph instead of a combinator DSL.

## File layout

FPP definitions are split across themed files:

| File | Role |
|---|---|
| `types.fpp` | External types and port declarations |
| `devices.fpp` | Component definitions and instance declarations |
| `stacks.fpp` | Infrastructure sub-topologies (`TcpipStack`, `SocketStack`, `DnsStack`) |
| `websites.fpp` | Composed web-server topologies (Unix, Xen/Solo5 variants) |
| `skeleton.fpp` | Minimal topologies matching mirage-skeleton examples |
| `server.ml` | User code: HTTPS dispatch, `Unix_socket_stack` wrapper |
| `htdocs/`, `tls/` | Static assets (crunched into `Htdocs_data`, `Tls_data`) |

Generated files (via `dune build`):

| File | Rule |
|---|---|
| `mirage.fpp` | Full namespace (concatenation of all themed `.fpp` files) |
| `mirage.ml` | Module type aliases (`ofpp to-ml --types`) |
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
    server.data -> data.get
    server.certs -> certs.get
    server.stack -> stack.provide
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
| `UnixNetwork` | single bound leaf | Flat (module alias + lazy) |

Fully-bound topologies generate a `let () = Lwt_main.run ...` entry
point when passed to `ofpp to-ml --topologies`.

## Generating code

```sh
# Module type aliases only (pass themed files)
ofpp to-ml --types types.fpp devices.fpp stacks.fpp websites.fpp

# Single topology with entry point
ofpp to-ml --topologies UnixWebsite types.fpp devices.fpp stacks.fpp websites.fpp

# Multiple topologies
ofpp to-ml --topologies UnixWebsite,UnixTestWebsite types.fpp devices.fpp stacks.fpp websites.fpp

# Skeleton examples (need skeleton.fpp too)
ofpp to-ml --topologies UnixDnsResolver types.fpp devices.fpp stacks.fpp skeleton.fpp
```

## Comparison with mirage-skeleton

The `skeleton.fpp` file contains minimal topologies matching
[mirage-skeleton](https://github.com/mirage/mirage-skeleton) examples.
Below is a side-by-side comparison of our generated output vs Mirage's.

### device-usage/network

Mirage's `main.ml` (essential parts, stripped of boilerplate):

```ocaml
module Unikernel_main__14 = Unikernel.Main(Tcpip_stack_socket.V4V6)

let udpv4v6_socket__11 = lazy (
  Udpv4v6_socket.connect ~ipv4_only:... ~ipv6_only:... ...)
let tcpv4v6_socket__12 = lazy (
  Tcpv4v6_socket.connect ~ipv4_only:... ~ipv6_only:... ...)
let tcpip_stack_socket_v4v6__13 = lazy (
  Tcpip_stack_socket.V4V6.connect _udpv4v6_socket__11 _tcpv4v6_socket__12)
let unikernel_main__14 = lazy (
  Unikernel_main__14.start _tcpip_stack_socket_v4v6__13)
```

Our `ofpp to-ml --topologies UnixNetwork`:

```ocaml
module Socket_stack = Tcpip_stack_socket.V4V6

let socket_stack = lazy (Socket_stack.connect ())
let () =
  Lwt_main.run begin
    let open Lwt.Syntax in
    let* _ = Lazy.force socket_stack in
    Lwt.return ()
  end
```

**Differences:** We treat the socket stack as opaque (one module alias)
rather than modelling its internal UDP/TCP sub-layers. Mirage adds the
`Unikernel.Main` functor for the user's unikernel code — we leave that
to the user. Clean module names vs mangled `__14` suffixes.

### device-usage/kv_ro

Mirage:

```ocaml
module Unikernel_main__12 = Unikernel.Main(Static_t)
let static_t__11 = lazy (Static_t.connect ())
let unikernel_main__12 = lazy (Unikernel_main__12.start _static_t__11)
```

Ours:

```ocaml
module Data = Static_t
let data = lazy (Data.connect ())
```

### applications/dns

Mirage (essential structure):

```ocaml
module Happy_eyeballs_mirage_make__14 = Happy_eyeballs_mirage.Make(Tcpip_stack_socket.V4V6)
module Dns_client_mirage_make__15 = Dns_client_mirage.Make(Tcpip_stack_socket.V4V6)(Happy_eyeballs_mirage_make__14)
module Unikernel_make__16 = Unikernel.Make(Dns_client_mirage_make__15)

let tcpip_stack_socket_v4v6__13 = lazy (
  Tcpip_stack_socket.V4V6.connect _udpv4v6_socket__11 _tcpv4v6_socket__12)
let happy_eyeballs_mirage_make__14 = lazy (
  Happy_eyeballs_mirage_make__14.connect_device ... _tcpip_stack_socket_v4v6__13)
let dns_client_mirage_make__15 = lazy (
  Dns_client_mirage_make__15.connect ...
    (_tcpip_stack_socket_v4v6__13, _happy_eyeballs_mirage_make__14))
let unikernel_make__16 = lazy (
  Unikernel_make__16.start _dns_client_mirage_make__15)
```

Ours:

```ocaml
module Socket_stack = Tcpip_stack_socket.V4V6
module Happy_eyeballs = Happy_eyeballs_mirage.Make(Socket_stack)
module Dns_client = Dns_client_mirage.Make(Socket_stack)(Happy_eyeballs)

let socket_stack = lazy (Socket_stack.connect ())
let happy_eyeballs = lazy (
  let open Lwt.Syntax in
  let* socket_stack = Lazy.force socket_stack in
  Happy_eyeballs.connect socket_stack)
let dns_client = lazy (
  let open Lwt.Syntax in
  let* socket_stack = Lazy.force socket_stack in
  let* happy_eyeballs = Lazy.force happy_eyeballs in
  Dns_client.connect socket_stack happy_eyeballs)
```

**Differences:** Same functor application chain, clean names. We use
`let*` (Lwt.Syntax) vs `>>=`. Our connect calls use the standard
signature; Mirage's uses library-specific signatures like
`connect_device` with optional args.

### applications/static_website_tls

Mirage:

```ocaml
module Conduit_mirage_tcp__16 = Conduit_mirage.TCP(Tcpip_stack_socket.V4V6)
module Conduit_mirage_tls__17 = Conduit_mirage.TLS(Conduit_mirage_tcp__16)
module Cohttp_mirage_server_make__18 = Cohttp_mirage.Server.Make(Conduit_mirage_tls__17)
module Dispatch_https__19 = Dispatch.HTTPS(Static_htdocs)(Static_tls)(Cohttp_mirage_server_make__18)

let static_htdocs__11 = lazy (Static_htdocs.connect ())
let static_tls__12 = lazy (Static_tls.connect ())
let conduit_mirage_tcp__16 = lazy (Lwt.return _stack)
let conduit_mirage_tls__17 = lazy (Lwt.return _conduit_tcp)
let cohttp_mirage_server_make__18 = lazy (
  Lwt.return (Cohttp_mirage_server_make__18.listen _conduit_tls))
let dispatch_https__19 = lazy (
  Dispatch_https__19.start _htdocs _tls _http_server)
```

Ours:

```ocaml
module Socket_stack = Tcpip_stack_socket.V4V6
module Data = Static_htdocs
module Certs = Static_tls
module Conduit_tcp = Conduit_mirage.TCP(Socket_stack)
module Conduit = Conduit_mirage.TLS(Conduit_tcp)
module Http = Cohttp_mirage.Server.Make(Conduit)

let socket_stack = lazy (Socket_stack.connect ())
let data = lazy (Data.connect ())
let certs = lazy (Certs.connect ())
```

**Differences:** Identical functor chain. Mirage adds the `Dispatch.HTTPS`
unikernel functor; our topologies model infrastructure only. Passive
components (conduit, HTTP server) get functor applications but no connect
calls in both systems.

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

## Runtime config via unconnected ports

Components can declare input ports that are intentionally left
unconnected in the topology.  These become labelled arguments on the
generated `connect` function:

```fpp
active component Ip {
  output port ipv4: IpWrite
  output port ipv6: IpWrite
  sync input port write: IpWrite
  sync input port ipv4_only: BoolConfig   @ unconnected -> ~ipv4_only
  sync input port ipv6_only: BoolConfig   @ unconnected -> ~ipv6_only
}
```

Generated connect call:
```ocaml
let connect ~cidr ~ipv4_only ~ipv6_only backend data certs =
  ...
  let* ipv4 = Ipv4.connect ~cidr eth arp in
  let* ip = Ip.connect ~ipv4_only ~ipv6_only ipv4 ipv6 in
  ...
```

## Component abstract types

Components can declare abstract types that appear in the generated
module type signatures.  This produces module types that closely match
the real Mirage interfaces:

```fpp
active component Kv {
  type Error
  type Key
  sync input port disconnect: Disconnect
  sync input port get: KvGet
  ...
}
```

Generated module type:
```ocaml
module type KV = sig
  type t
  type error
  type key
  val disconnect : t -> unit Lwt.t
  val get : t -> key -> (string, error) result Lwt.t
  ...
end
```

## Known limitations

- **`connect` signature assumption.** The generated code assumes each
  active component has `connect : deps -> t Lwt.t`.  Libraries with
  non-standard lifecycle functions (e.g. `Happy_eyeballs_mirage`
  uses `connect_device`, `Dns_client_mirage.connect` takes a tuple)
  require a user-provided wrapper component.

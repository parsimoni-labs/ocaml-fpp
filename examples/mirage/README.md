# MirageOS Example

This example models the MirageOS module composition layer in FPP.  The FPP topology graph drives functor application order and
`connect` call wiring — the same job `functoria` does today, but
expressed as a typed connection graph instead of a combinator DSL.

## Two-layer design

FPP models MirageOS in two independent layers:

### Layer 1: Module construction (current)

What FPP models today:

- **Dependency graph** — which modules plug into which functors
  (output ports → `sync input port connect`)
- **Functor application** — `module Arp = Arp.Make(Ethernet)` from the
  connection graph
- **Assembly order** — topological sort determines `connect` call
  sequence via lazy bindings
- **Connect signatures** — port types encode function parameters
  (labeled, positional, typed)

What is **out of scope** at layer 1:

- What functions a module exposes (`write`, `get`, `listen`, etc.)
- Module type signatures
- How end-users call the module after construction

Every component declares `sync input port connect` as its universal
connection target.  Output ports name constructor dependencies.  The
target port name is a validation gate — codegen ignores it and derives
`connect` call arguments from the source-side output port declaration
order.

### Layer 2: Module interface (future, for interop)

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

| File | Role |
|---|---|
| `mirage.fpp` | Types, ports, components, instances, sub-topologies, and deployment topologies |
| `server.ml` | User code: HTTPS dispatch, `Unix_socket_stack` wrapper |
| `htdocs/`, `tls/` | Static assets (crunched into `Htdocs_data`, `Tls_data`) |
| `main.ml` | Topology + entry point (`ofpp to-ml --topologies UnixWebsite`) |

## Port types as connect signatures

Port definitions encode the `connect` function signature:

```fpp
port SocketConnect(ipv4Only: bool, ipv6Only: bool, _0: Cidr, _1: Cidr6)
port BlockConnect(name: string)
port NetifConnect(_0: string)
```

### Parameter conventions

| FPP param | Generated OCaml | C++ (future) |
|---|---|---|
| `name: Type` | `~name:value` (labeled) | `name = value` |
| `_N: Type` | positional arg | positional arg |
| struct-typed param | expand fields as labeled args | expand fields |
| struct field with default | optional labeled (omitted if unset) | has default |
| `external param key: T` | Cmdliner runtime term | runtime config |

- **Named params** — become OCaml labeled arguments (`~name:value`)
- **Positional params** — `_N` prefix marks positional arguments
- **Struct-typed params** — struct fields expand as labeled args; fields with
  defaults become optional and are omitted when not overridden
- **External types** — string values auto-convert via `of_string_exn`
  (e.g. `"10.0.0.2/24"` → `Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24"`)

### Instance param overrides

Per-topology build-time values use native FPP syntax:

```fpp
topology TcpipStack {
  instance ipv4(cidr = "10.0.0.2/24")
  instance ip(ipv4Only = false, ipv6Only = false)
  ...
}

topology SocketStack {
  instance udpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
  ...
}

topology UnixBlock {
  instance ramdisk(name = "block-test")
  ...
}
```

Values are FPP expressions (bool, int, string, identifier), making them
target-independent for FFI generation.  Unresolved required params cause
OCaml compile errors; unresolved optional params (struct fields with
defaults) are silently omitted.  Use `external param` on the component
for runtime-configurable values (Cmdliner terms).

## Component correspondence

Each FPP component defines a module type; each instance becomes a module
(via functor application or leaf alias). Output ports declare functor
dependencies; the connection graph determines application order.

| FPP component | OCaml module | Functor | Package |
|---|---|---|---|
| `Backend` | *(leaf parameter)* | — | `mirage-vnetif` |
| `Udpv4v6_socket` | `Udpv4v6_socket` | — | `tcpip.stack-socket` |
| `Tcpv4v6_socket` | `Tcpv4v6_socket` | — | `tcpip.stack-socket` |
| `Stackv4v6.Make` | `Stackv4v6.Make` | `Make(Udp, Tcp)` | `tcpip.stack-socket` |
| `Vnetif.Make` | `Vnetif.Make` | `Make(Backend)` | `mirage-vnetif` |
| `Ethernet.Make` | `Ethernet.Make` | `Make(Net)` | `ethernet` |
| `Arp.Make` | `Arp.Make` | `Make(Ethernet)` | `arp.mirage` |
| `Static_ipv4.Make` | `Static_ipv4.Make` | `Make(Ethernet, Arp)` | `tcpip.ipv4` |
| `Ipv6.Make` | `Ipv6.Make` | `Make(Net, Ethernet)` | `tcpip.ipv6` |
| `Tcpip_stack_direct.IPV4V6` | `Tcpip_stack_direct.IPV4V6` | `IPV4V6(Ipv4, Ipv6)` | `tcpip.stack-direct` |
| `Icmpv4.Make` | `Icmpv4.Make` | `Make(Ipv4)` | `tcpip.icmpv4` |
| `Udp.Make` | `Udp.Make` | `Make(IP)` | `tcpip.udp` |
| `Tcp.Flow.Make` | `Tcp.Flow.Make` | `Make(IP)` | `tcpip.tcp` |
| `Tcpip_stack_direct.MakeV4V6` | `Tcpip_stack_direct.MakeV4V6` | `MakeV4V6(Net,Eth,Arp,IP,Icmp,Udp,Tcp)` | `tcpip.stack-direct` |
| `Netif` | `Netif` | — | `mirage-net-unix` |
| `Block` / `Ramdisk` | *(leaf)* | — | `mirage-block` |
| `Kv` | *(leaf parameter)* | — | `mirage-kv` |
| `Block_kv` | `Tar_mirage.Make_KV_RO` / `Fat.KV_RO` | via `@ ocaml.module` | `tar-mirage` / `fat-filesystem` |
| `Conduit_tcp.Make` | `Conduit_tcp.Make` | `Make(Stack)` | `conduit-mirage` |
| `Happy_eyeballs_mirage.Make` | `Happy_eyeballs_mirage.Make` | `Make(Stack)` | `happy-eyeballs-mirage` |
| `Dns_resolver.Make` | `Dns_resolver.Make` | `Make(Stack, HE)` | `dns-client-mirage` |
| `Paf_mirage.Server` | `Paf_mirage.Server` | `Server(Tcp)` | `paf` |
| `Http_mirage_client.Make` | `Http_mirage_client.Make` | `Make(Tcp, Mimic)` | `http-mirage-client` |
| `Syslog.Udp` / `.Tcp` / `.Tls` | syslog variants | `Make(Stack)` | `logs-syslog` |
| `Git_mirage.Tcp` / `.Ssh` / `.Http` | git transport | `Make(Tcp, Mimic)` | `git-mirage` |

## Annotation correspondence

| FPP annotation | Effect | Example |
|---|---|---|
| `@ ocaml.module X.Y` | Override default module path | `@ ocaml.module Tcpip_stack_direct.IPV4V6` on `Ip` |
| `@ ocaml.type T` | Map abstract FPP type to OCaml type | `@ ocaml.type Ipaddr.V4.Prefix.t` on `type Cidr` |

`@ ocaml.module` is purely a name override.  Every instance already has
a module name — its instance name, capitalised (e.g. `instance eth` →
module `Eth`).  The annotation replaces that default when the OCaml
module path differs (e.g. `@ ocaml.module Tcpip_stack_direct.IPV4V6` on
`Ip`).  The connection graph determines whether the path is used as a
functor application (non-leaf instance with outgoing connections) or a
module alias (leaf instance with no outgoing connections).

Default functor path for non-leaf instances: `ComponentName.Make`
(e.g. `Ethernet` → `Ethernet.Make`).

## Topology composition

Sub-topologies are shared via `import`:

```
topology SocketStack {
  instance udpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
  instance tcpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
  instance stackv4v6
  connections Connect {
    stackv4v6.udp -> udpv4v6_socket.connect
    stackv4v6.tcp -> tcpv4v6_socket.connect
  }
}

topology UnixNetwork {
  import SocketStack
  instance stackv4v6
  instance stack_app
  connections Start {
    stack_app.stack -> stackv4v6.connect
  }
}
```

The parent topology wires cross-boundary connections (here: plugging
the socket stack into the application).

## Configuration and runtime parameters

FPP provides three mechanisms for configuration, resolved in priority order:

1. **Instance param overrides** `instance name(param = value)` —
   native FPP syntax for build-time values, target-independent.
2. **Init spec** (`phase N "code"`) on the instance — target-specific
   code string, keyed by parameter index.
3. **`external param`** on the component — declares a runtime-configurable
   value.  The codegen generates a `Mirage_runtime.register_arg` call
   (Cmdliner term) so the value becomes a command-line flag at runtime.

Port params (from typed connect ports) must be resolved via instance
overrides.  Unresolved required params cause OCaml compile errors;
unresolved optional params (struct fields with defaults) are silently
omitted, letting the callee use its default.

### F Prime param protocol

Components with `external param` declare `param get port` and
`param set port` as required by the F Prime spec.  These ports use the
built-in `Fw.PrmGet` / `Fw.PrmSet` port types, which have fixed
semantics in F Prime: they define the protocol for reading and writing
runtime parameters.

The OCaml backend implements this protocol via Cmdliner CLI arguments.
A C++ backend would implement it via the F Prime parameter database.
The FPP source is the same — `external param` declarations and param
ports are target-independent; only the backend implementation differs.

```fpp
passive component Ccm_block {
  import Mirage_block.S
  external param key: string       @ the param declaration
  param get port prmGetOut          @ F Prime param protocol
  param set port prmSetOut
  output port block: serial
}
```

The param ports are built-in infrastructure handled internally by the
codegen — they do not appear in the topology connection graph and do
not generate functor dependencies.

## Entry points

Topologies passed to `ofpp to-ml --topologies` additionally generate a
`Mirage_runtime`-based entry point.

### Functor semantics

The generated code uses OCaml's default **applicative** functor semantics:
`module X = F(A)` and `module Y = F(A)` share types (`X.t = Y.t`).
This is correct for MirageOS — components that share the same TCP/IP
stack should agree on types.

For **runtime initialisation**, the codegen uses lazy
bindings: each `let x = lazy (...)` block forces its dependencies via
`Lazy.force`. This mirrors generative behaviour at the value level —
each `Lazy.force` creates a fresh runtime value — while keeping
applicative type sharing at the module level.

## Generating code

```sh
# Single topology with entry point
ofpp to-ml --topologies UnixNetwork mirage.fpp

# Multiple topologies
ofpp to-ml --topologies UnixNetwork,DirectNetwork mirage.fpp
```

## Key design differences from Mirage/Functoria

| Aspect | Mirage | ofpp |
|---|---|---|
| Input format | OCaml combinator DSL (`config.ml`) | FPP connection graph |
| Module naming | Mangled (`Tcpip_stack_socket_v4v6__13`) | Clean (`Socket_stack`) |
| Async style | `Lwt.Infix` (`>>=`) | `Lwt.Syntax` (`let*`) |
| Runtime args | `Mirage_runtime.register_arg` | `Mirage_runtime.register_arg` from `external param` |
| Connect params | Hardcoded in combinator | Port types + instance overrides |
| Application module | Included in `main.ml` | Left to user |
| Boilerplate | ~90 lines per example | ~10-20 lines per example |

## Known limitations

- **Option types.** FPP lacks option types, so optional positional args
  must use identifier values like `None` in instance overrides.
- **`connect` signature assumption.** The generated code assumes each
  active component has `connect : deps -> t Lwt.t`.  Libraries with
  non-standard lifecycle functions (e.g. `Happy_eyeballs_mirage`
  uses `connect_device`, `Dns_resolver` uses `start`) declare
  the appropriate `sync input port` name.

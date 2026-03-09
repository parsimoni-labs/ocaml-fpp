# MirageOS Example

This example models the MirageOS module composition layer in FPP.  The FPP
topology graph drives functor application order and `connect` call wiring —
the same job `functoria` does today, but expressed as a typed connection
graph instead of a combinator DSL.

## Two-layer design

FPP models MirageOS in two layers, both expressed in the same topology:

### Layer 1: Construction (`connections Connect`)

Construction connections drive the OCaml codegen:

- **Functor application** — `module Arp = Arp.Make(Ethernet)` from
  output port → `connect` connections
- **Assembly order** — topological sort determines `connect` call
  sequence via lazy bindings
- **Connect signatures** — port types encode function parameters
  (labeled, positional, typed)

| FPP construct | OCaml codegen |
|---|---|
| `output port eth: serial` | functor argument |
| `ethernet.net -> net.connect` | `module Ethernet = Ethernet.Make(Net)` |
| `instance ipv4(cidr = "...")` | `~cidr:(of_string_exn "...")` |
| `external param device: string` | `Mirage_runtime.register_arg` |

### Layer 2: Dataflow (`connections Dataflow`)

Dataflow connections model runtime callback wiring — which component
sends data to which.  These are validated by the checker (port names
must exist, instances must be declared) but skipped by the OCaml codegen.

| FPP construct | Meaning |
|---|---|
| `output port on_frame: serial` | callback: "I produce frames" |
| `sync input port $input: EthInput` | handler: "I receive frames" |
| `net.on_frame -> ethernet.$input` | net's frame callback calls ethernet's input |

Callbacks are output ports.  The connection graph wires who receives
them.  This is defunctionalisation: the higher-order callback
`listen : (buf -> unit) -> unit` becomes a data message on an output
port, dispatched by the connection graph.

### Both layers in one topology

```fpp
topology TcpipStack {
  instance net
  instance ethernet

  @ Layer 1: construction (functor deps)
  connections Connect {
    ethernet.net -> net.connect
  }

  @ Layer 2: dataflow (runtime callbacks)
  connections Dataflow {
    net.on_frame -> ethernet.$input
    ethernet.on_arp -> arp.recv
    ethernet.on_ipv4 -> ipv4.$input
    ethernet.on_ipv6 -> ipv6.$input
  }
}
```

Construction connections generate OCaml code.  Dataflow connections are
structural documentation validated by the checker — future backends may
generate callback registration code from them.

## File layout

| File | Role |
|---|---|
| `mirage.fpp` | Shared device catalogue: types, ports, components, device instances, sub-topologies |
| `*/config.fpp` | Per-app config: unikernel component, app instances, deployment topology |
| `*/unikernel.ml` | User code: the unikernel implementation |
| `*/main.ml` | Generated entry point (`ofpp to-ml --topologies T mirage.fpp config.fpp`) |

## Port types

### Connect signatures (Layer 1)

Port definitions encode the `connect` function signature:

```fpp
port SocketConnect(ipv4Only: bool, ipv6Only: bool, _0: Cidr, _1: Cidr6)
port BlockConnect(name: string)
port NetifConnect(_0: string)
```

| FPP param | Generated OCaml | C++ (future) |
|---|---|---|
| `name: Type` | `~name:value` (labeled) | `name = value` |
| `_N: Type` | positional arg | positional arg |
| struct-typed param | expand fields as labeled args | expand fields |
| struct field with default | optional labeled (omitted if unset) | has default |
| `external param key: T` | Cmdliner runtime term | runtime config |

### Device operations (Layer 2)

Typed ports on interfaces model the module type contract:

```fpp
port BlockRead(offset: U64, _0: Buffer) -> BlockError
port NetWrite(size: U32, _0: Buffer) -> NetError
port IpInput(src: IpAddr, dst: IpAddr, _0: Buffer)
```

These generate `module type` declarations (`.mli`: real sig path,
`.ml`: expanded from FPP ports for compiler checking).

### Callbacks as output ports

A callback like `Mirage_net.listen : t -> (buf -> unit Lwt.t) -> unit Lwt.t`
is two things: a registration point and a reverse data flow.  In FPP:

```fpp
passive component Netif {
  import Mirage_net.S
  sync input port connect: NetifConnect   @ Layer 1: how to construct
  output port on_frame: serial            @ Layer 2: callback direction
}
```

The component declares what data it produces (output port).  The
topology wires who receives it (connection).  No higher-order types
needed — the graph is a defunctionalised representation of the
callback program.

## Instance param overrides

Per-topology build-time values use native FPP syntax:

```fpp
topology TcpipStack {
  instance ipv4(cidr = "10.0.0.2/24")
  instance ip(ipv4Only = false, ipv6Only = false)
}

topology SocketStack {
  instance udpv4v6_socket(ipv4Only = false, ipv6Only = false, _0 = "0.0.0.0/0", _1 = None)
}
```

Values are FPP expressions (bool, int, string, identifier), making them
target-independent.  Unresolved required params cause OCaml compile
errors; unresolved optional params (struct fields with defaults) are
silently omitted.

## Annotation correspondence

| FPP annotation | Effect | Example |
|---|---|---|
| `@ ocaml.type T` | Map FPP type to OCaml type | `@ ocaml.type Ipaddr.V4.Prefix.t` on `type Cidr` |

This is the only annotation needed.  Module names and signatures are
derived from FPP structure directly:

- Instance name → OCaml module name (capitalised: `instance ethernet` → `Ethernet`)
- Component path → functor path (`instance ipv4: Static_ipv4.Make` → `Static_ipv4.Make(...)`)
- `import Mirage_block.S` → `module type Ramdisk = Mirage_block.S` (from interface path)
- Unqualified component → default `Instance_name.Make`

## Topology composition

Sub-topologies are shared via `import`:

```fpp
topology SocketStack {
  instance udpv4v6_socket(...)
  instance tcpv4v6_socket(...)
  instance stackv4v6
  connections Connect {
    stackv4v6.udp -> udpv4v6_socket.connect
    stackv4v6.tcp -> tcpv4v6_socket.connect
  }
}

topology UnixNetwork {
  import SocketStack
  instance stackv4v6
  instance unikernel
  connections Start {
    unikernel.stack -> stackv4v6.connect
  }
}
```

## Configuration and runtime parameters

FPP provides three mechanisms for configuration:

1. **Instance param overrides** `instance name(param = value)` —
   build-time values, target-independent.
2. **Init spec** (`phase N "code"`) — target-specific code string.
3. **`external param`** — runtime-configurable value (Cmdliner term).

### F Prime param protocol

Components with `external param` declare `param get port` and
`param set port` as required by the F Prime spec.  The OCaml backend
implements this via Cmdliner CLI arguments; a C++ backend would use
the F Prime parameter database.

```fpp
passive component Ccm_block {
  import Mirage_block.S
  external param key: string
  param get port prmGetOut
  param set port prmSetOut
  output port block: serial
}
```

## Entry points

Topologies passed to `ofpp to-ml --topologies` generate a
`Mirage_runtime`-based entry point.

The generated code uses **applicative** functor semantics for type
sharing, and **lazy bindings** for runtime initialisation (generative
at the value level).

## Generating code

```sh
# Single topology
ofpp to-ml --topologies UnixNetwork mirage.fpp device-usage/network/config.fpp

# Multiple topologies
ofpp to-ml --topologies UnixNetwork,UnixDns mirage.fpp \
  device-usage/network/config.fpp applications/dns/config.fpp
```

## Key design differences from Mirage/Functoria

| Aspect | Mirage | ofpp |
|---|---|---|
| Input format | OCaml combinator DSL (`config.ml`) | FPP: `mirage.fpp` + `config.fpp` |
| Module naming | Mangled (`Tcpip_stack_socket_v4v6__13`) | Clean (`Socket_stack`) |
| Async style | `Lwt.Infix` (`>>=`) | `Lwt.Syntax` (`let*`) |
| Runtime args | `Mirage_runtime.register_arg` | `external param` |
| Connect params | Hardcoded in combinator | Port types + instance overrides |
| Callbacks | Not modeled | Output ports + `Dataflow` connections |
| Boilerplate | ~90 lines per example | ~10-20 lines per example |

## Known limitations

- **Option types.** FPP lacks option types, so optional positional args
  must use identifier values like `None` in instance overrides.
- **`connect` signature assumption.** Libraries with non-standard
  lifecycle functions (e.g. `connect_device`, `start`) declare
  the appropriate `sync input port` name.
- **Dataflow codegen.** `connections Dataflow` is structural
  documentation validated by the checker.  The OCaml backend does not
  yet generate callback registration code from dataflow connections.

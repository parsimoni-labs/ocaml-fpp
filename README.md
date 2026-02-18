# ofpp -- OCaml FPP

An experimental OCaml front-end for
[FPP](https://nasa.github.io/fpp/fpp-users-guide.html), the modelling
language of NASA's [F Prime](https://nasa.github.io/fprime/) flight software
framework. The project exists to explore the F Prime ecosystem from a
different angle -- using OCaml's type system and tooling to parse, analyse,
and eventually generate tests from FPP specifications.

## About FPP

FPP (F Prime Prime) is designed and maintained by the F Prime team at NASA
JPL. It provides a compact, typed language for defining flight software
components, ports, state machines, topologies, and their connections. The
reference compiler is written in Scala and lives in the
[nasa/fpp](https://github.com/nasa/fpp) repository. All language design
decisions, semantics, and the authoritative specification belong to that
upstream project.

**ofpp is not affiliated with or endorsed by NASA or JPL.** It is an
independent experiment that consumes the same `.fpp` source files.

## What ofpp does today

ofpp ships a single binary, `ofpp`, built on a Menhir parser that covers the
**complete FPP grammar** -- components (active, passive, queued), ports,
commands, events, telemetry channels, parameters, data products, state
machines, topologies, connection graphs, annotations, and significant-newline
handling inside bracket expressions. The parser produces zero Menhir conflicts
and is validated against all 670 upstream test files imported from the
reference compiler's test suite (35 categories covering codegen, state
machines, topologies, ports, and more).

### `ofpp check`

```
ofpp check [--verbose] [--skip ANALYSIS] Components/**/*.fpp
```

Parse one or more FPP files and report syntax or semantic errors with
`file:line:col` locations.

#### Core checks (always enabled)

These detect semantic errors that must be fixed. They match the upstream
`fpp-check` behaviour and are validated against 101 upstream state machine
test files.

1. **Name redefinition** -- duplicate state, choice, action, guard, signal,
   constant, and type names
2. **Initial transition validation** -- exactly one initial transition per SM
   and per parent state
3. **Undefined reference detection** -- undefined actions, choices, guards,
   signals, states, constants, and types, with contextual hints (e.g.
   "a guard 'x' exists")
4. **Duplicate signal transitions** -- at most one transition per signal per
   state
5. **Reachability analysis** -- every state and choice must be reachable from
   the initial node
6. **Choice cycle detection** -- no cycles in the choice-only subgraph
7. **Default value validation** -- type-compatible default values (struct
   fields, string-to-numeric, enums)
8. **Format string validation** -- format specifiers on non-numeric types,
   alias resolution
9. **Initial transition scope** -- initial transitions target local
   states/choices only
10. **Typed element checking** -- signal, action, and guard type compatibility,
    widening (I16 to I32, F32 to F64), choice type propagation

#### Warning-level analyses (can be disabled with `--skip`)

These detect suspicious patterns that may indicate bugs but are not
necessarily errors. Each can be individually disabled.

- **Signal coverage** (`--skip coverage`) -- for each leaf state, warns about
  signals not handled directly or via inheritance from ancestors. Novel to ofpp
  -- the upstream compiler does not perform this analysis.
- **Liveness** (`--skip liveness`) -- detects groups of states forming a cycle
  with no exit path to a terminal state, using Tarjan's SCC algorithm with
  backward reachability analysis.
- **Unused declarations** (`--skip unused`) -- reports actions, guards, and
  signals declared but never referenced in any transition, choice, or
  entry/exit action.
- **Transition shadowing** (`--skip shadowing`) -- warns when a child state
  handles a signal that an ancestor already handles. The child's handler
  overrides the parent's, which may be intentional or accidental. Inspired by
  SCADE and Stateflow edit-time checks.
- **Deadlock detection** (`--skip deadlock`) -- warns about leaf states with
  no outgoing transitions and no ancestor handler, when the state machine
  declares at least one signal. Such states can never react to any event.
- **Guard completeness** (`--skip completeness`) -- warns when a choice
  definition has no `else` branch. A missing else means the choice may fail
  to transition if no guard evaluates to true.

In verbose mode, the output includes component, state machine, and topology
counts per file. Warnings are displayed in a formatted table.

### `ofpp dot`

```
ofpp dot [--sm NAME] model.fpp | dot -Tpng -o sm.png
```

Render state machines as Graphviz DOT digraphs. Hierarchical states become
cluster subgraphs, choices become diamond nodes, and signal transitions become
labelled edges. Initial transitions are shown as dashed edges from synthetic
start points. Entry and exit actions appear in the state node labels.

This feature is not available in the upstream FPP toolchain.

## What is planned

The roadmap (see [TODO.md](TODO.md)) covers three directions:

- **Static analysis** (`ofpp check`). Topology wiring validation (port type
  and direction compatibility, duplicate connections, async dependency cycles),
  and component-level checks. Additional state machine checks: guard mutual
  exclusivity, numeric range checking, bounded response analysis.
- **Test generation** (`ofpp test`). Derive test cases -- GTest stubs,
  portable JSON vectors, or QCheck property-based tests -- from FPP model
  structure.
- **OCaml code generation** (`ofpp to-ml`). Generate OCaml types and state
  machine modules from FPP definitions. Research stage.

## Building

ofpp requires OCaml >= 4.14, Dune >= 3.0, and Menhir.

```
opam install . --deps-only
dune build
dune exec -- ofpp check test/upstream/component/*.fpp
```

## Running the tests

```
dune runtest
```

This runs 841+ tests: unit tests (Alcotest) covering core error checks,
warning-level analyses, and environment construction, plus 670 upstream file
parse tests, 91 upstream state machine check tests, and a cram test suite for
the CLI.

## Benchmarks

```
dune exec -- bench/bench.exe
```

Runs the analysis pipeline over all 670 upstream test files. Supports
`MEMTRACE=file.ctf` for memory profiling via memtrace.

## Acknowledgements

FPP is the work of the F Prime team at NASA's Jet Propulsion Laboratory. The
language specification, reference compiler, and upstream test suite are
maintained in [nasa/fpp](https://github.com/nasa/fpp). The 670 test files
under `test/upstream/` are imported directly from that repository. ofpp would
not exist without their publicly available work.

## Licence

MIT. See [LICENSE](LICENSE).

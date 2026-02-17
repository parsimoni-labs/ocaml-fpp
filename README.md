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
ofpp check [--verbose] [--warn] Components/**/*.fpp
```

Parse one or more FPP files and report syntax or semantic errors with
`file:line:col` locations. Runs 12 static analysis checks on state machines:

1. **Name redefinition detection** -- duplicate state/choice/action/guard/signal/constant names
2. **Initial transition validation** -- exactly one initial transition per SM and per parent state
3. **Undefined reference detection** -- undefined actions, choices, guards, signals, states, constants
4. **Duplicate signal transitions** -- at most one transition per signal per state
5. **Reachability analysis** -- every state and choice must be reachable from the initial node
6. **Choice cycle detection** -- no cycles in the choice-only subgraph (deadlock prevention)
7. **Undefined type references** -- type names used but not defined
8. **Undefined constant references** -- constant names used but not defined
9. **Default value validation** -- type-compatible default values
10. **Format string validation** -- format specifiers match element types
11. **Initial transition scope** -- initial transitions target local states/choices
12. **Typed element checking** -- type compatibility for signals, actions, and guards

With `--warn`, ofpp also performs **signal coverage analysis** (novel to ofpp,
not in the upstream compiler): at each leaf state, it warns about signals that
are not handled, accounting for inherited handlers from ancestor states. This
catches gaps like an `error` signal missing from a RESET state.

In verbose mode, the output includes component, state machine, and topology
counts per file.

## What is planned

The roadmap (see [TODO.md](TODO.md)) covers three directions:

- **Static analysis** (`ofpp check`). Topology wiring validation (port type
  and direction compatibility, duplicate connections, async dependency cycles),
  and component-level checks.
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

This runs 817 tests: unit tests (Alcotest) covering all 12 analysis checks
plus 4 signal coverage tests, 670 upstream file parse tests, 91 upstream
state machine check tests, and a cram test suite for the CLI.

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

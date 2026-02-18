# ofpp -- OCaml FPP

An experimental OCaml front-end for
[FPP](https://nasa.github.io/fpp/fpp-users-guide.html), the modelling
language of NASA's [F Prime](https://nasa.github.io/fprime/) flight software
framework. The project exists to explore the F Prime ecosystem from a
different angle -- using OCaml's type system and tooling to parse, analyse,
and eventually generate tests from FPP specifications.

**ofpp is not affiliated with or endorsed by NASA or JPL.** It is an
independent experiment that consumes the same `.fpp` source files.

## Quick example

A thermostat controller defined in FPP:

```fpp
state machine Thermostat {
  action startHeating
  action startCooling
  action stopHvac

  guard tooHot
  guard tooCold

  signal tempReading
  signal shutdown

  initial enter Idle

  state Idle {
    on tempReading if tooCold enter Heating
    on tempReading if tooHot enter Cooling
    on shutdown enter Off
  }

  state Heating {
    entry do { startHeating }
    on tempReading do { stopHvac } enter Idle
    on shutdown do { stopHvac } enter Off
  }

  state Cooling {
    entry do { startCooling }
    on tempReading do { stopHvac } enter Idle
    on shutdown do { stopHvac } enter Off
  }

  state Off
}
```

`ofpp dot -o thermostat.svg Thermostat.fpp` renders:

![Thermostat state machine](doc/thermostat.svg)

A more complex example with nested states and choices (satellite deployment
sequence):

![Deployment sequence state machine](doc/deploy.svg)

## About FPP

FPP (F Prime Prime) is designed and maintained by the F Prime team at NASA
JPL. It provides a compact, typed language for defining flight software
components, ports, state machines, topologies, and their connections. The
reference compiler is written in Scala and lives in the
[nasa/fpp](https://github.com/nasa/fpp) repository. All language design
decisions, semantics, and the authoritative specification belong to that
upstream project.

## Overview

ofpp ships a single binary built on a Menhir parser that covers the **complete
FPP grammar** -- components (active, passive, queued), ports, commands, events,
telemetry channels, parameters, data products, state machines, topologies,
connection graphs, annotations, and significant-newline handling inside bracket
expressions. The parser produces zero Menhir conflicts and is validated against
all 670 upstream test files imported from the reference compiler's test suite
(35 categories covering codegen, state machines, topologies, ports, and more).

Two subcommands are available: `ofpp check` for static analysis, and `ofpp dot`
for state machine visualisation.

## `ofpp check` -- static analysis

```
ofpp check [--verbose] [-w SPEC] [-e SPEC] FILE...
```

Parse one or more FPP files and report syntax or semantic errors with
`file:line:col` locations. In verbose mode the output includes component, state
machine, and topology counts per file; warnings are displayed in a formatted
table. Exit code is 0 when all files pass, 1 otherwise.

### Core checks

These detect semantic errors that must be fixed. They match the upstream
`fpp-check` behaviour and are validated against 101 upstream state machine test
files.

The checker verifies **name uniqueness** across states, choices, actions,
guards, signals, constants, and types -- a duplicate definition is always an
error. Every state machine and every parent state must have exactly one
**initial transition**, and that transition must target a local state or choice
(**scope validation**). All references to actions, guards, signals, states,
choices, constants, and types are resolved; **undefined references** produce
errors with contextual hints (e.g. "a guard 'x' exists, did you mean that?").
At most one transition per signal per state is allowed (**duplicate signal
detection**).

Beyond naming, the checker performs **reachability analysis** to ensure every
state and choice is reachable from the initial node, and **choice cycle
detection** to reject infinite choice-to-choice loops. **Type checking** covers
signal, action, and guard type compatibility with automatic widening (I16 to
I32, F32 to F64) and choice type propagation. **Default value validation**
catches type-incompatible defaults in struct fields, string-to-numeric
conversions, and enum defaults. **Format string validation** rejects format
specifiers on non-numeric types and resolves type aliases.

### Warning-level analyses

These detect suspicious patterns that may indicate bugs but are not necessarily
errors. Each can be individually controlled with `-w` (enable/disable) and
promoted to errors with `-e`.

| Analysis | Name | Abbrev. | Description |
|---|---|---|---|
| Signal coverage | `coverage` | `cov` | Checks that every leaf state handles every declared signal, either directly or via inheritance from an ancestor. Novel to ofpp. |
| Liveness | `liveness` | `liv` | Detects groups of states forming a cycle with no exit path, using Tarjan's SCC algorithm. |
| Unused declarations | `unused` | `unu` | Reports actions, guards, and signals declared but never referenced. |
| Transition shadowing | `shadowing` | `sha` | Warns when a child state handles a signal that an ancestor already handles. |
| Deadlock detection | `deadlock` | `dea` | Warns about leaf states with no outgoing transitions and no ancestor handler. |
| Guard completeness | `completeness` | `com` | Warns when a choice has no `else` branch. |

### Warning and error specs

The `-w`/`--warning` flag controls which analyses are enabled. The
`-e`/`--error` flag promotes enabled analyses to error level (causing a
non-zero exit code when triggered). An analysis disabled by `-w` cannot be
promoted by `-e`.

Specs are comma-separated. Each item is optionally prefixed with `+` (enable)
or `-` (disable); bare names enable. The special name `all` targets every
analysis. Both full names and 3-letter abbreviations are accepted.

### Examples

```
ofpp check Components/**/*.fpp
ofpp check --verbose model.fpp
ofpp check --warning=-cov model.fpp              # disable coverage
ofpp check --warning=-all,+deadlock model.fpp    # only deadlock
ofpp check --error=all model.fpp                 # all warnings are errors
ofpp check --error=cov,dea --warning=-sha m.fpp  # promote coverage+deadlock, disable shadowing
```

## `ofpp dot` -- state machine diagrams

```
ofpp dot [-o FILE] [--sm NAME] FILE...
```

Render state machines as [D2](https://d2lang.com) diagrams. D2 is a modern
diagramming language with clean default styling and native support for
hierarchical containers -- a good fit for nested state machines. The output uses
the ELK layout engine for correct routing of cross-container transitions.

Hierarchical states become D2 containers with nested children. Choices appear as
diamond-shaped nodes. Transitions are labelled using standard UML statechart
notation: `signal [guard] / actions`. Initial transitions originate from small
filled circles. Entry and exit actions appear inside state node labels.

Without `-o`, D2 text is written to stdout. With `-o`, the output format is
determined by the file extension: `.svg`, `.png`, and `.pdf` invoke `d2`
automatically to render an image; any other extension writes D2 text to the
file. The `--sm` flag selects a single state machine by name when a file
contains multiple definitions.

This feature is not available in the upstream FPP toolchain.

### Examples

```
ofpp dot model.fpp                        # D2 text to stdout
ofpp dot -o diagram.svg model.fpp         # render to SVG
ofpp dot -o diagram.png model.fpp         # render to PNG
ofpp dot model.fpp | d2 - diagram.svg     # manual pipe to d2
ofpp dot --sm Controller model.fpp        # select one SM
```

Rendering to image formats requires [d2](https://d2lang.com) to be installed.
D2 is a single Go binary available on Linux, macOS, and Windows.

## What is planned

The roadmap (see [TODO.md](TODO.md)) covers three directions.

**Static analysis** extends `ofpp check` to topology wiring validation -- port
type and direction compatibility, duplicate connections, async dependency
cycles -- and to component-level checks. Additional state machine analyses
include guard mutual exclusivity, numeric range checking, and bounded response
analysis.

**Test generation** (`ofpp test`) will derive test cases from FPP model
structure: GTest stubs for C++ projects, portable JSON vectors for any test
runner, and QCheck property-based tests for OCaml harnesses.

**OCaml code generation** (`ofpp to-ml`) will generate OCaml types and state
machine modules from FPP definitions. This is at the research stage.

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

This runs 850+ tests: unit tests (Alcotest) covering core error checks,
warning-level analyses, D2 rendering, and environment construction, plus 670
upstream file parse tests, 91 upstream state machine check tests, and a cram
test suite for the CLI.

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

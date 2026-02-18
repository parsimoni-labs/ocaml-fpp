# TODO - ofpp (OCaml FPP)

## Done

- [x] Repository setup, dune-project, opam, .ocamlformat
- [x] Parser (ast, lexer, parser, fpp.ml/mli)
- [x] CLI foundation (`ofpp check <files>`)
- [x] Import 670 upstream NASA FPP test files, all passing
- [x] Zero Menhir conflicts
- [x] Significant newlines (virtual comma insertion in `[...]` brackets)
- [x] Full FPP grammar: empty enums/structs, trailing commas,
      post-annotations after commas, `phase` expressions, `locate dictionary
      type`, optional graph targets, `every` throttle, contextual keywords,
      semicolons as whitespace
- [x] Cram tests for `ofpp check` CLI

## Static Analysis (`ofpp check`)

### State Machine Analysis

**Real-world example**: `fprime-community/fprime-sensors` has an
`ImuStateMachine` (5 states, 4 signals, 5 actions) where signal coverage
analysis reveals gaps: `error` is unhandled in RESET, `success` is unhandled
in RUN, and `reconfigure` is unhandled in 4 of 5 states. This is exactly the
kind of issue static analysis should catch.

Based on the upstream test suite at [`nasa/fpp/.../test/state_machine/`](https://github.com/nasa/fpp/tree/main/compiler/tools/fpp-check/test/state_machine):

- [x] **Transition graph reachability** -- every state and choice must be
      reachable from the initial node
- [x] **Choice cycle detection** -- no cycles in the choice-only subgraph
      (deadlock prevention)
- [x] **Initial transition validation** -- exactly one initial transition per
      SM and per parent state with substates
- [x] **Name redefinition detection** -- duplicate state/choice/action/guard/
      signal/constant names
- [x] **Signal use validation** -- at most one transition per signal per state
- [x] **Typed element checking** -- type compatibility for signals, actions,
      and guards flowing through choices (widening rules for numeric types)
- [x] **Signal coverage analysis** (warning) -- detect unhandled signals in
      leaf states, accounting for inherited handlers from ancestor states
- [x] **Undefined reference detection** -- undefined actions, choices, guards,
      signals, states, constants
- [ ] **Non-determinism detection** -- multiple transitions on same signal
      from same state, overlapping guards
- [ ] **Liveness properties** -- every state eventually reaches a terminal
      state (under fairness)

### Topology Analysis

- [ ] **Required ports connected** -- all required ports have connections
- [ ] **Port type compatibility** -- connected ports have matching types
- [ ] **Port direction compatibility** -- output to input only
- [ ] **No duplicate connections** to single sync input ports
- [ ] **Async dependency cycle detection** -- circular async message flows
- [ ] **Priority inversion warnings**
- [ ] **Rate group coverage** -- every active component is scheduled

### Component Validation

- [ ] **Active/queued async requirement** -- active and queued components must
      have at least one async input port
- [ ] **State machine instance placement** -- SM instances require async queue
      (not allowed in passive components)

## Test Generation (`ofpp test`)

Three output formats, all driven by FPP model analysis:

### `--format=gtest` (default, standalone C++)

Generate filled GTest test cases using standard F Prime test macros:

- [ ] **Command coverage** -- all opcodes, parameter combinations
- [ ] **Event coverage** -- all event types, all severity levels
- [ ] **Telemetry coverage** -- all channels, update modes
- [ ] **Parameter coverage** -- all params, validation paths
- [ ] **Port coverage** -- all invocations (sync/async/guarded)
- [ ] **State machine coverage** -- all states, transitions, guards
- [ ] **Boundary tests** -- type boundaries (U8: 0/255, I16: -32768/32767, etc.)
- [ ] **Component kind tests** --
  - Passive: sync execution, guarded port serialisation
  - Active: queue full, overflow, dispatch ordering, priority
  - Queued: queue bounds, poke semantics

### `--format=vectors` (portable JSON)

- [ ] JSON test case output consumable by any test runner

### `--format=ocaml` (property-based, requires fprime-ocaml)

- [ ] QCheck generators for FPP types
- [ ] QCheck-STM state machine conformance tests
- [ ] Crowbar AFL-guided fuzzing

## Code Generation (`ofpp to-ml`)

- [ ] Generate OCaml types from FPP definitions
- [ ] Generate state machine modules with variant types and transitions
- [ ] Generate test harness stubs

## Infrastructure

- [ ] CI (GitHub Actions: Ubuntu, macOS; OCaml 4.14, 5.x)
- [ ] Publish to opam
- [ ] API documentation (odoc)
- [ ] Examples directory

## Research / Future

- [ ] NuSMV model export for formal verification
- [ ] Mutation testing (mutate spec, verify tests catch it)
- [ ] Symbolic execution through guards
- [ ] Assume/guarantee contracts (AGREE-style) for topologies
- [ ] WCET propagation and timing analysis

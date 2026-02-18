# TODO - ofpp (OCaml FPP)

## Static Analysis (`ofpp check`)

### State Machine Analysis

Based on the upstream test suite at [`nasa/fpp/.../test/state_machine/`](https://github.com/nasa/fpp/tree/main/compiler/tools/fpp-check/test/state_machine):

#### Core checks (always enabled, 101 upstream tests pass)

- [x] **Name redefinition** -- duplicate actions, guards, signals, states,
      choices, constants, types
- [x] **Initial transition validation** -- missing, multiple, scope
      correctness (parent/child)
- [x] **Undefined references** -- actions, guards, signals, states, choices,
      constants, types; with contextual hints ("a guard 'x' exists")
- [x] **Duplicate signal transitions** -- same signal handled twice in one
      state
- [x] **Reachability** -- unreachable states and choices
- [x] **Choice cycle detection** -- infinite choice-to-choice loops
- [x] **Type checking** -- signal/action/guard type compatibility, widening
      (I16→I32, F32→F64), choice type propagation
- [x] **Default value validation** -- struct extra fields, string-to-numeric
      conversion, enum defaults
- [x] **Format string validation** -- format specifiers on non-numeric types,
      alias resolution

#### Warning-level analyses (can be disabled with `--skip`)

- [x] **Signal coverage** -- signals not handled in leaf states (accounting
      for inheritance from parent states)
- [x] **Liveness** -- cycle detection via Tarjan SCC + backward reachability
      from terminal states
- [x] **Unused declarations** -- actions, guards, signals declared but never
      referenced

#### Future

- [ ] **Numeric range checking** -- literal values fit in declared types
      (e.g. `-1` in `U32`) ([nasa/fpp#102](https://github.com/nasa/fpp/issues/102))
- [ ] **Guard completeness** -- warn when choice guard outcomes are not
      exhaustive
- [ ] **Buffer size validation** -- FPP data types fit in uplink/downlink
      buffers ([nasa/fpp#679](https://github.com/nasa/fpp/issues/679))

### Topology Analysis

- [ ] **Required ports connected** -- all required ports have connections
- [ ] **Port type compatibility** -- connected ports have matching types
- [ ] **Port direction compatibility** -- output to input only
- [ ] **No duplicate connections** to single sync input ports
- [ ] **Async dependency cycle detection** -- circular async message flows
- [ ] **Rate group coverage** -- every active component is scheduled

### Component Validation

- [ ] **Active/queued async requirement** -- active and queued components must
      have at least one async input port
- [ ] **State machine instance placement** -- SM instances require async queue
      (not allowed in passive components)

## Visualization (`ofpp dot`)

- [ ] **State machine → Graphviz/DOT** -- render state machines as visual
      graphs (not available in the upstream fpp toolchain)

## Test Generation (`ofpp test`)

Three output formats, all driven by FPP model analysis:

### `--format=gtest` (default, standalone C++)

Generate filled GTest test cases using standard F Prime test macros:

- [ ] **State machine coverage** -- all states, transitions, guards
- [ ] **Command coverage** -- all opcodes, parameter combinations
- [ ] **Event coverage** -- all event types, all severity levels
- [ ] **Telemetry coverage** -- all channels, update modes
- [ ] **Port coverage** -- all invocations (sync/async/guarded)
- [ ] **Boundary tests** -- type boundaries (U8: 0/255, I16: -32768/32767)
- [ ] **Component kind tests** -- passive (sync, guarded), active (queue,
      dispatch, priority), queued (bounds, poke)

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

# TODO - ofpp (OCaml FPP)

## Static Analysis (`ofpp check`)

### State Machine Analysis

Based on the upstream test suite at [`nasa/fpp/.../test/state_machine/`](https://github.com/nasa/fpp/tree/main/compiler/tools/fpp-check/test/state_machine):

- [ ] **Non-determinism detection** -- multiple transitions on same signal
      from same state, overlapping guards
- [x] **Liveness properties** -- cycle detection via Tarjan SCC + backward
      reachability from terminal states

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

## Visualization (`ofpp dot`)

- [ ] **State machine → Graphviz/DOT** -- render state machines as visual
      graphs (not available in the upstream fpp toolchain)

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

## Model Checking (`ofpp check`)

Motivated by upstream issues
([nasa/fpp#679](https://github.com/nasa/fpp/issues/679),
[nasa/fpp#911](https://github.com/nasa/fpp/issues/911)):

- [ ] **Buffer size validation** -- check that FPP data types fit in
      uplink/downlink buffers at compile time (nasa/fpp#679)
- [ ] **Guard completeness** -- ensure choice branches cover all cases;
      warn when guard outcomes are not exhaustive

## Research / Future

- [ ] NuSMV model export for formal verification
- [ ] Mutation testing (mutate spec, verify tests catch it)
- [ ] Symbolic execution through guards
- [ ] Assume/guarantee contracts (AGREE-style) for topologies
- [ ] WCET propagation and timing analysis

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

#### Future: safety and certification checks

Prioritised by safety impact and implementation feasibility. References to
standards (DO-178C, MISRA, SCADE) and real-world incidents motivate each check.

##### Structural and determinism

- [ ] **Transition shadowing** -- warn when a child state handles a signal
      that an ancestor already handles; may be intentional (override) or
      accidental. SCADE and
      [Stateflow](https://www.mathworks.com/help/stateflow/ug/stateflow-edit-time-checks.html)
      flag this as an edit-time check.
- [ ] **Sink state / deadlock** -- warn about leaf states with no outgoing
      transitions (potential deadlock). The
      [Hitomi X-ray satellite (2016)](https://en.wikipedia.org/wiki/Hitomi_(satellite))
      was destroyed by a cascading state machine failure. HDL lint tools flag
      this as a primary FSM defect
      ([Semiengineering](https://semiengineering.com/developing-robust-finite-state-machines-code-with-lint-tools/)).
- [ ] **Guard mutual exclusivity** -- when a state has multiple guarded
      transitions on the same signal, warn if guards are not provably
      exclusive. Non-exclusive guards create nondeterminism; SCADE formally
      proves determinism and completeness
      ([SCADE semantics](https://www.di.ens.fr/~pouzet/bib/tase17.pdf)).
      Intel's
      [Safe State Machine](https://www.intel.com/content/www/us/en/docs/programmable/683283/18-1/safe-state-machine.html)
      guidelines require this.

##### Type and range safety

- [ ] **Numeric range checking** -- literal values fit in declared types
      (e.g. `-1` in `U32`)
      ([nasa/fpp#102](https://github.com/nasa/fpp/issues/102)). Related:
      FpySequencer unit test arithmetic overflow
      ([fprime#4397](https://github.com/nasa/fprime/issues/4397),
      [fprime#4325](https://github.com/nasa/fprime/issues/4325)).
- [ ] **Buffer size validation** -- verify serialised size of typed signals
      fits in `FW_SM_SIGNAL_BUFFER_MAX_SIZE` (default 128 bytes, defined in
      `FpConstants.fpp`). Runtime overflows cause assertions and potential
      flight software crashes
      ([nasa/fpp#679](https://github.com/nasa/fpp/issues/679),
      [fprime#1626](https://github.com/nasa/fprime/issues/1626)).

##### Coverage and completeness (DO-178C alignment)

- [ ] **Guard completeness** -- warn when choice guard outcomes are not
      exhaustive. UML specification states models without else branches are
      "ill-formed"
      ([UML state machine](https://en.wikipedia.org/wiki/UML_state_machine)).
- [ ] **Dead transition detection** -- transitions whose guard conditions
      can never be true given the state machine structure. Stateflow's
      "dead logic detection" identifies these
      ([MathWorks](https://www.mathworks.com/help/stateflow/ug/stateflow-edit-time-checks.html)).
      Supports DO-178C Section 6.4.4.2 structural coverage
      ([LDRA](https://ldra.com/do-178c/)).
- [ ] **Bounded response** -- for each signal, verify it is handled within
      a bounded number of transitions (no unbounded deferral). In flight
      software, unbounded deferral of safety-critical commands (e.g. abort)
      can be catastrophic. Related to JPL's "Power of 10" Rule 2
      ([Holzmann](https://spinroot.com/gerard/pdf/P10.pdf)).

##### Interface and composition

- [ ] **Signal-port mapping** -- when an internal SM is embedded in a
      component, verify every SM signal has a corresponding port or event
      source. The Boeing Starliner OFT-1 (2019) had a valve mapping error
      ([SpaceNews](https://spacenews.com/starliner-investigation-finds-numerous-problems-in-boeing-software-development-process/)).
      Requires cross-component analysis.
- [ ] **Queue capacity analysis** -- static estimation of whether queue
      sizes are sufficient given signal patterns. The FpySequencer
      experienced queue-full assertion crashes during intensive sequences
      ([fprime#4359](https://github.com/nasa/fprime/issues/4359),
      [fprime#4155](https://github.com/nasa/fprime/issues/4155)).

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

- [ ] **NuSMV / nuXmv model export** -- formal verification of safety and
      liveness properties via CTL/LTL model checking. DO-333 (Formal Methods
      Supplement to DO-178C) grants certification credit for model checking
      ([NASA DO-333 case studies](https://ntrs.nasa.gov/citations/20140004055),
      [MDPI formal analysis](https://www.mdpi.com/2079-9292/9/2/327)).
- [ ] **State invariant expressibility** -- allow users to declare
      properties that must hold in a given state (e.g.
      `AG(in_ARMED -> sensors_valid)`), verified statically or flagged for
      test generation.
- [ ] **Mutation testing** -- mutate spec, verify tests catch it.
- [ ] **Symbolic execution through guards** -- constraint solving to
      identify dead guards and prove mutual exclusivity.
- [ ] **Assume/guarantee contracts** (AGREE-style) for topologies.
- [ ] **WCET propagation and timing analysis**.

### References

- [DO-178C structural coverage](https://ldra.com/do-178c/) (LDRA)
- [The Power of 10](https://spinroot.com/gerard/pdf/P10.pdf) (Holzmann, JPL)
- [Developing robust FSMs with lint tools](https://semiengineering.com/developing-robust-finite-state-machines-code-with-lint-tools/) (Semiengineering)
- [Stateflow edit-time checks](https://www.mathworks.com/help/stateflow/ug/stateflow-edit-time-checks.html) (MathWorks)
- [SCADE formal semantics](https://www.di.ens.fr/~pouzet/bib/tase17.pdf) (Pouzet et al.)
- [NASA software error categorisation](https://ntrs.nasa.gov/api/citations/20230012154/downloads/8-17-23%2020230012154.pdf) (NTRS)
- [Mars Pathfinder priority inversion](https://www.rapitasystems.com/blog/what-really-happened-software-mars-pathfinder-spacecraft) (Rapita)
- [Boeing Starliner software investigation](https://spacenews.com/starliner-investigation-finds-numerous-problems-in-boeing-software-development-process/) (SpaceNews)
- [MISRA compliance and static analysis](https://www.perforce.com/blog/qac/misra-compliance-static-analysis) (Perforce)
- [Intel Safe State Machine guidelines](https://www.intel.com/content/www/us/en/docs/programmable/683283/18-1/safe-state-machine.html)
- [F Prime state machines documentation](https://fprime.jpl.nasa.gov/latest/docs/user-manual/framework/state-machines/)
- [FPP language specification v3.1.0](https://nasa.github.io/fpp/fpp-spec.html)

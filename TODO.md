# TODO - ofpp (OCaml FPP)

## Static Analysis (`ofpp check`)

### Upstream Analysis Pipeline

The upstream `fpp-check` compiler performs semantic analysis in a
[20-step sequential pipeline](https://github.com/nasa/fpp/wiki/Checking-Semantics),
operating on a list of translation units. The table below maps each step to the
corresponding ofpp module (if implemented).

| Step | Upstream phase | ofpp module | Status |
|------|---------------|-------------|--------|
| 1 | Create empty analysis | `Check_tu_env` | done (`build_tu_env`) |
| 2 | [Enter symbols](https://github.com/nasa/fpp/wiki/Enter-Symbols) | `Check_tu_env` | done (symbol environment) |
| 3 | Construct implied use map | — | not started |
| 4 | [Check uses](https://github.com/nasa/fpp/wiki/Check-Uses) (build use-def map) | — | not started |
| 5 | [Check use-def cycles](https://github.com/nasa/fpp/wiki/Check-Use-Def-Cycles) | `Check_sym` | done (dependency cycle DFS) |
| 6 | Check type uses | `Check_sym` | done (symbol kind validation) |
| 7 | Check expression types | `Check_def` | done (expression validation) |
| 8 | Check framework definitions | — | not applicable |
| 9 | Evaluate implied enum constants | — | not started |
| 10 | Evaluate constant expressions | `Check_tu_env` | done (`eval_expr`) |
| 11 | Finalise type definitions | — | not started |
| 12 | Check port definitions | `Check_comp` | done (`check_port_def`) |
| 13 | Check interface definitions | `Check_comp` | done (`check_interface`) |
| 14 | Check component definitions | `Check_comp` | done (full validation) |
| 15 | Check component instance defs | `Check_topo` | done (`check_component_instance`) |
| 16 | [Check state machine definitions](https://github.com/nasa/fpp/wiki/Check-State-Machine-Definitions) | `Check_core` + `Check_warn` | done (101 + 6 analyses) |
| 17 | Check topology definitions | `Check_topo` | partial (instances, imports, patterns) |
| 18 | Check location specifiers | `Check_def` | done (`check_spec_locs`) |
| 19 | Check dictionary definitions | — | not started |
| 20 | Construct dictionary map | — | not started |

Additional cross-cutting check not in the upstream pipeline:

- `Check_redef` — duplicate definition detection at every scope level
  (upstream distributes this across Enter Symbols via name-symbol map errors)

Reference pages:
[Analysis](https://github.com/nasa/fpp/wiki/Analysis) ·
[Analysis Data Structure](https://github.com/nasa/fpp/wiki/Analysis-Data-Structure) ·
[State Machine Analysis Data Structure](https://github.com/nasa/fpp/wiki/State-Machine-Analysis-Data-Structure) ·
[Computing Dependencies](https://github.com/nasa/fpp/wiki/Computing-Dependencies)

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
- [x] **Transition shadowing** -- child state handles a signal that an
      ancestor already handles (may be intentional override or accidental)
- [x] **Deadlock detection** -- leaf states with no outgoing transitions
      (direct or inherited) when signals are defined
- [x] **Guard completeness** -- choices without else branches (may fail to
      transition if no guard evaluates to true)

#### Future: safety and certification checks

Prioritised by safety impact and implementation feasibility. References to
standards (DO-178C, MISRA, SCADE) and real-world incidents motivate each check.

##### Structural and determinism
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
- [ ] **Infinity exclusion** -- reject non-finite floating-point constants
      (e.g. `constant a = 1e10000`). Also covers F64→F32 overflow producing
      infinity
      ([nasa/fpp#345](https://github.com/nasa/fpp/issues/345), related to
      [nasa/fpp#102](https://github.com/nasa/fpp/issues/102)).
- [ ] **Buffer size validation** -- verify serialised size of typed signals
      fits in `FW_SM_SIGNAL_BUFFER_MAX_SIZE` (default 128 bytes, defined in
      `FpConstants.fpp`). Runtime overflows cause assertions and potential
      flight software crashes
      ([nasa/fpp#679](https://github.com/nasa/fpp/issues/679),
      [fprime#1626](https://github.com/nasa/fprime/issues/1626)).

##### Coverage and completeness (DO-178C alignment)

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

#### UML tool landscape

Survey of checks in industry UML statechart tools and how they map to ofpp.
FPP state machines are deliberately simpler than full UML statecharts (no
parallel regions, no during actions, no event broadcast, no backtracking), so
many tool-specific checks do not apply.

##### Already implemented in ofpp

Checks present in at least one major tool that ofpp already covers:

- Unreachable states/junctions --
  [Stateflow](https://www.mathworks.com/help/stateflow/ug/stateflow-edit-time-checks.html),
  [Yakindu](https://en.wikipedia.org/wiki/YAKINDU_Statechart_Tools),
  [Majzik & Pataricza](https://www.academia.edu/14748792/Completeness_and_consistency_analysis_of_UML_statechart_specifications)
- Dead ends / trap states -- Yakindu, Majzik & Pataricza
- Missing default (initial) transition -- Stateflow
- Transition shadowing -- Stateflow, Yakindu
- Unused declarations -- Yakindu (unused variable/event), Stateflow (unused
  function)
- Guard completeness (no unconditional escape from choice) -- Stateflow
  (junction escape), Yakindu (exit point default trigger)
- Undefined references -- Yakindu (unknown event)
- Liveness / cycle detection -- ofpp (Tarjan SCC)

##### Already in TODO (above)

- Guard mutual exclusivity -- SCADE Design Verifier (determinism proof),
  Majzik & Pataricza (non-deterministic / conflicting transitions)
- Numeric range / overflow -- Stateflow (data range violations), SCADE
  (arithmetic overflow)
- Infinity / NaN -- SCADE (predefined runtime error checks)
- Dead transition detection -- Stateflow (dead logic detection)

##### Not applicable to FPP

These checks exist in UML tools but target constructs FPP does not have:

- Parallel region trigger conflicts -- Yakindu (same trigger, different
  action across orthogonal regions). FPP has no parallel regions.
- Always-triggered transition livelock -- Yakindu. FPP transitions require
  explicit signals.
- Unconditional exit prevents during actions -- Stateflow. FPP has no during
  actions.
- Cyclic event broadcast -- Stateflow. FPP signals are external, not
  self-broadcast.
- Dangling transitions -- Stateflow. Not applicable to textual (non-graphical)
  models.
- Unexpected backtracking -- Stateflow. FPP has no backtracking semantics.

### Topology Analysis

The parser already has full AST support for topologies, connection graphs
(direct and pattern-based), component instances, and port numbering. All 99
upstream topology test files (across 7 categories) parse correctly. No semantic
checks are implemented yet.

The upstream `fpp-check` compiler performs approximately 24 topology checks.
These fall into three tiers for ofpp implementation.

#### Tier 1: replicate upstream checks (99 upstream test files)

These checks are well-specified by the upstream test suite and can be validated
against it, following the same pattern used for state machine checks.

- [ ] **Port direction validation** -- connections must go from output to input
      (11 tests in `connection_direct/`)
- [ ] **Port type matching** -- connected ports must have compatible types;
      serial ports act as a wildcard but cannot connect to ports with return
      types
- [ ] **Port/instance existence** -- connection endpoints must reference
      defined port instances in defined component instances
- [ ] **Instance membership** -- component instances referenced in connections
      must be members of the topology
- [ ] **Port number bounds** -- explicit array indices must be within declared
      port size
- [ ] **Duplicate output connections** -- no two connections at the same output
      port index (11 tests in `port_numbering/`)
- [ ] **Internal port prohibition** -- internal ports cannot appear in topology
      connections
- [ ] **Connection pattern validation** -- command, event, health, param,
      telemetry, text\_event, and time patterns require specific special ports
      on source and target instances (31 tests in `connection_pattern/`)
- [ ] **Matched port numbering** -- paired port arrays must have consistent
      indices, no missing partners, no implicit duplicates (7 tests in
      `port_matching/`)
- [ ] **Duplicate instance/import/pattern** -- uniqueness of instances,
      imported topologies, and pattern kinds within a topology (6 tests in
      `top_import/`)

#### Tier 2: novel checks (not in upstream, high practical value)

These are inspired by AUTOSAR, Simulink, Capella, and AADL tools. They
represent the highest-value additions beyond what `fpp-check` provides.

- [ ] **Unconnected required port detection** -- warn when an input port has
      no incoming connection. The single most common wiring bug across all
      surveyed tools (AUTOSAR mandates this, Capella's I\_20 rule, Simulink's
      Model Advisor). Should be a warning, not an error, since some ports are
      intentionally left unconnected (2 tests in `unconnected/`)
- [ ] **Connection graph cycle detection** -- flag cycles in synchronous port
      connections that could cause deadlock. Analogous to Simulink's algebraic
      loop detection
- [ ] **Rate group coverage** -- warn when an active component is not
      scheduled by any rate group. Missing scheduling is a common deployment
      error

#### Tier 3: deeper analysis (large systems)

- [ ] **Cross-topology import conflict detection** -- when `import` brings
      connections from another topology, check for conflicting connections to
      the same port
- [ ] **Port numbering gap detection** -- array indices should be contiguous
      (0..N-1); gaps suggest missing connections
- [ ] **Pattern completeness** -- when a connection pattern is used, verify
      all eligible component instances participate

### Component Validation

Based on upstream test suites: `component/` (21 tests),
`component_instance_def/` (19 tests), `component_instance_spec/` (3 tests),
`port_instance/` (31 tests). All parse correctly; no semantic checks
implemented yet.

- [ ] **Active/queued async requirement** -- active and queued components must
      have at least one async input port
- [ ] **State machine instance placement** -- SM instances require async queue
      (not allowed in passive components)
- [ ] **Port instance validation** -- async input restrictions (no return
      values, no ref params on passive components), priority and queue-full
      policy validation (31 upstream tests)
- [ ] **Special port requirements** -- command ports require matching product
      recv ports; duplicate special ports rejected

### Upstream Check Coverage

All 670 upstream test files are imported and parse correctly. Semantic check
coverage by category:

| Category | Files | Checks | Status |
|----------|-------|--------|--------|
| `state_machine/` | 91 | error + warning | done (101 pass/fail tests) |
| `connection_direct/` | 11 | none | parse only |
| `connection_pattern/` | 31 | none | parse only |
| `port_instance/` | 31 | none | parse only |
| `port_matching/` | 7 | none | parse only |
| `port_numbering/` | 11 | none | parse only |
| `top_import/` | 6 | none | parse only |
| `unconnected/` | 2 | none | parse only |
| `component/` | 21 | none | parse only |
| `component_instance_def/` | 19 | none | parse only |
| `state_machine_instance/` | 7 | none | parse only |
| `array/` | 26 | none | parse only |
| `enum/` | 15 | none | parse only |
| `struct/` | 17 | none | parse only |
| `expr/` | 12 | none | parse only |
| `constant/` | 10 | none | parse only |
| `type/` | 7 | none | parse only |
| others (14 categories) | 246 | none | parse only |

## Visualization (`ofpp dot`)

- [x] **State machine → D2** -- render state machines as D2 diagrams with
      ELK layout, hierarchical containers, and UML statechart notation.
      Auto-invokes `d2` for SVG/PNG/PDF via `-o` flag
- [ ] **Topology → D2** -- render topologies as connection diagrams showing
      component instances, port wiring, and connection patterns

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

## Proposed Upstream Language Features

Language features proposed or discussed in the upstream `nasa/fpp` issue tracker
that would unlock new analysis opportunities. These require spec and syntax
changes upstream before ofpp can implement corresponding checks.

### State machine extensions

- [ ] **Scoped signals, actions, and guards**
      ([nasa/fpp#592](https://github.com/nasa/fpp/issues/592)) -- define
      signals/actions/guards inside a state, visible only to that state and its
      substates. Currently all declarations are globally visible within the SM.
      **New checks:** scope violation detection (signal raised from wrong
      context), scoped signal exhaustiveness, tighter unused-declaration
      analysis. This is the FPP equivalent of Yakindu's per-region trigger
      validation.
- [ ] **If-else in state transition specifiers**
      ([nasa/fpp#911](https://github.com/nasa/fpp/issues/911)) -- inline
      guard-else on transitions without requiring a choice pseudostate. Related
      to local transitions
      ([statecharts.dev](https://statecharts.dev/glossary/local-transition.html)).
      **New checks:** redundant guard detection (if + else trivially covers all
      cases), local transition correctness (no unnecessary exit/entry actions).
- [ ] **Default actions on signals**
      ([nasa/fpp#628](https://github.com/nasa/fpp/issues/628)) -- specify a
      fallback action for a signal at the SM level, applied to all states that
      do not explicitly handle it. Currently requires a wrapping parent state.
      **New checks:** shadowing becomes richer (default vs explicit handler),
      coverage analysis changes (default satisfies coverage).
- [ ] **Emit events on state machine signals**
      ([nasa/fpp#593](https://github.com/nasa/fpp/issues/593)) -- attach
      component events directly to SM signal handlers instead of routing
      through action implementations.
      **New checks:** signal-event type compatibility, event argument arity
      matching, event severity consistency.
- [ ] **Auto-generated state enumeration**
      ([nasa/fpp#615](https://github.com/nasa/fpp/issues/615)) -- generate an
      FPP enum representing the SM's state set, usable in telemetry and events.
      Semantics are implemented upstream; code gen is pending.
      **New checks:** telemetry coverage (SM state should be reported
      somewhere), enum exhaustiveness in downstream switch statements.

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
- [Formalizing UML State Machines for Automated Verification -- A Survey](https://dl.acm.org/doi/10.1145/3579821) (ACM Computing Surveys, 2024)
- [Completeness and consistency analysis of UML statechart specifications](https://www.academia.edu/14748792/Completeness_and_consistency_analysis_of_UML_statechart_specifications) (Majzik, Pataricza, Pap)
- [SCADE Design Verifier](https://www.ansys.com/products/embedded-software/ansys-scade-suite) (Ansys)
- [Yakindu / itemis CREATE statechart tools](https://en.wikipedia.org/wiki/YAKINDU_Statechart_Tools)
- [Stateflow common modeling errors](https://www.mathworks.com/help/stateflow/ug/common-modeling-errors-the-debugger-can-detect.html) (MathWorks)
- [Local transitions](https://statecharts.dev/glossary/local-transition.html) (statecharts.dev)

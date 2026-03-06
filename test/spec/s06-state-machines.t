FPP Spec §6 — State Machine Behavior Elements
===============================================

§6.1 Action definitions — with and without types

  $ cat > t.fpp <<EOF
  > state machine Actions {
  >   signal Go
  >   action simple
  >   action typed: U32
  >   state Idle { on Go do simple enter Idle }
  >   initial enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:4:9: warning in SM 'Actions': unused action 'typed'
  ✓ t.fpp

§6.2 Choice definitions — if/else branching

  $ cat > t.fpp <<EOF
  > state machine Choosy {
  >   signal Check
  >   guard ready
  >   guard valid
  >   action prepare
  >   choice Route {
  >     if ready do prepare enter Running
  >     if valid enter Standby
  >     else enter Error
  >   }
  >   state Idle { on Check enter Route }
  >   state Running { on Check enter Idle }
  >   state Standby { on Check enter Idle }
  >   state Error { on Check enter Idle }
  >   initial enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:14:8: warning in SM 'Choosy': states {'Error', 'Idle', 'Running', 'Standby'} form a cycle with no exit
  ✓ t.fpp

§6.3 Do expressions — internal transitions (do without enter)

  $ cat > t.fpp <<EOF
  > state machine Internal {
  >   signal Tick
  >   signal Done
  >   action count
  >   state Active {
  >     on Tick do count
  >     on Done enter Finished
  >   }
  >   state Finished { }
  >   initial enter Active
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬───────────┬──────────┬───────────────────────────────────────────────────╮
  │   │ Location  │ SM       │ Warning                                           │
  ├───┼───────────┼──────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:9:8 │ Internal │ signal 'Done' not handled in state 'Finished'     │
  │ ! │ t.fpp:9:8 │ Internal │ signal 'Tick' not handled in state 'Finished'     │
  │ ! │ t.fpp:9:8 │ Internal │ state 'Finished' has no outgoing transitions      │
  │   │           │          │ (potential deadlock)                              │
  ╰───┴───────────┴──────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§6.4 Guard definitions — with and without types

  $ cat > t.fpp <<EOF
  > state machine Guarded {
  >   signal Go
  >   guard simple
  >   guard typed: U32
  >   state Idle { on Go if simple enter Idle }
  >   initial enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:4:8: warning in SM 'Guarded': unused guard 'typed'
  ✓ t.fpp

§6.5 Initial transition specifier — with actions

  $ cat > t.fpp <<EOF
  > state machine Init {
  >   signal Go
  >   action setup
  >   state Idle { on Go enter Idle }
  >   initial do setup enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§6.5 Initial transition specifier — with multiple actions

  $ cat > t.fpp <<EOF
  > state machine Init2 {
  >   signal Go
  >   action a1
  >   action a2
  >   state Idle { on Go enter Idle }
  >   initial do { a1, a2 } enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§6.6 Signal definitions — with and without types

  $ cat > t.fpp <<EOF
  > state machine Signals {
  >   signal Simple
  >   signal Data: U32
  >   signal Config: F64
  >   state Idle {
  >     on Simple enter Idle
  >     on Data enter Idle
  >     on Config enter Idle
  >   }
  >   initial enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§6.7 State definitions — nested states with initial

  $ cat > t.fpp <<EOF
  > state machine Nested {
  >   signal A
  >   signal B
  >   state Outer {
  >     state Inner1 { on A enter Inner2 }
  >     state Inner2 { on B enter Inner1 }
  >     initial enter Inner1
  >   }
  >   initial enter Outer
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬────────────┬────────┬──────────────────────────────────────────╮
  │   │ Location   │ SM     │ Warning                                  │
  ├───┼────────────┼────────┼──────────────────────────────────────────┤
  │ ! │ t.fpp:5:10 │ Nested │ signal 'B' not handled in state 'Inner1' │
  │ ! │ t.fpp:6:10 │ Nested │ signal 'A' not handled in state 'Inner2' │
  ╰───┴────────────┴────────┴──────────────────────────────────────────╯
  
  ✓ t.fpp

§6.8/6.9 State entry/exit specifiers

  $ cat > t.fpp <<EOF
  > state machine Lifecycle {
  >   signal Go
  >   action initAction
  >   action cleanupAction
  >   state Active {
  >     entry do initAction
  >     exit do cleanupAction
  >     on Go enter Active
  >   }
  >   initial enter Active
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§6.8/6.9 Multiple entry/exit actions (brace syntax)

  $ cat > t.fpp <<EOF
  > state machine MultiAction {
  >   signal Go
  >   action a1
  >   action a2
  >   action a3
  >   state Idle {
  >     entry do { a1, a2 }
  >     exit do { a2, a3 }
  >     on Go enter Idle
  >   }
  >   initial enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§6.10 State transition specifiers — signal + guard + actions + enter

  $ cat > t.fpp <<EOF
  > state machine Full {
  >   signal Ev
  >   action act
  >   guard check
  >   state A { on Ev if check do act enter B }
  >   state B { on Ev enter A }
  >   initial enter A
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:5:8: warning in SM 'Full': states {'A', 'B'} form a cycle with no exit
  ✓ t.fpp

§6.10 Transition with multiple actions

  $ cat > t.fpp <<EOF
  > state machine MultiAct {
  >   signal Go
  >   action first
  >   action second
  >   state A { on Go do { first, second } enter A }
  >   initial enter A
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

External (bodyless) state machine

  $ cat > t.fpp <<EOF
  > state machine External
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

State machine with type definitions inside

  $ cat > t.fpp <<EOF
  > state machine TypedMachine {
  >   type Measurement
  >   type Threshold = F64
  >   enum Status { Ok, Error }
  >   struct Data { value: F64, status: Status }
  >   array Readings = [4] Data
  >   constant MAX_RETRIES = 3
  >   signal Go
  >   state Idle { on Go enter Idle }
  >   initial enter Idle
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

State machine with include specifier

  $ cat > inc.fpp <<EOF
  > EOF
  $ cat > t.fpp <<EOF
  > state machine Partial {
  >   signal Go
  >   state Idle { on Go enter Idle }
  >   initial enter Idle
  >   include "inc.fpp"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

State with include specifier

  $ cat > inc.fpp <<EOF
  > EOF
  $ cat > t.fpp <<EOF
  > state machine S {
  >   signal Go
  >   state Main {
  >     on Go enter Main
  >     include "inc.fpp"
  >   }
  >   initial enter Main
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

State machine instance in component

  $ cat > t.fpp <<EOF
  > state machine Counter {
  >   signal Tick
  >   action count
  >   state Counting { on Tick do count }
  >   initial enter Counting
  > }
  > active component Timed {
  >   state machine instance counter: Counter priority 5 assert
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

State machine instance — queue full options

  $ cat > t.fpp <<EOF
  > state machine Sm {
  >   signal Go
  >   state Idle { on Go enter Idle }
  >   initial enter Idle
  > }
  > active component C1 { state machine instance s1: Sm assert }
  > active component C2 { state machine instance s2: Sm drop }
  > active component C3 { state machine instance s3: Sm block }
  > active component C4 { state machine instance s4: Sm hook }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

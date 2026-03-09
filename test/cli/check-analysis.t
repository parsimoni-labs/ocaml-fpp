Valid state machine passes
  $ cat > ok.fpp <<EOF
  > state machine M {
  >   action a
  >   guard g
  >   signal s
  >   initial enter C
  >   choice C { if g do { a } enter S else enter S }
  >   state S { on s enter S }
  > }
  > EOF
  $ ofpp check ok.fpp
  ✓ ok.fpp

Duplicate action name
  $ cat > dup_action.fpp <<EOF
  > state machine M {
  >   action a
  >   action a
  > }
  > EOF
  $ ofpp check dup_action.fpp
  ! dup_action.fpp:3:9: warning in SM 'M': unused action 'a'
  ✗ dup_action.fpp:3:9: error in SM 'M': duplicate action 'a' (first defined at dup_action.fpp:2:9)
  ✗ dup_action.fpp:2:2: error in SM 'M': state machine has no initial transition
  
  ✗ 1/1 file failed
  [1]




Missing initial transition
  $ cat > no_init.fpp <<EOF
  > state machine M {
  >   state S
  > }
  > EOF
  $ ofpp check no_init.fpp
  ✗ no_init.fpp:2:2: error in SM 'M': state machine has no initial transition
  ✗ no_init.fpp:2:8: error in SM 'M': unreachable state 'S'
  
  ✗ 1/1 file failed
  [1]




Multiple initial transitions
  $ cat > multi_init.fpp <<EOF
  > state machine M {
  >   initial enter S
  >   initial enter T
  >   state S
  >   state T
  > }
  > EOF
  $ ofpp check multi_init.fpp
  ✗ multi_init.fpp:3:2: error in SM 'M': state machine has multiple initial transitions
  
  ✗ 1/1 file failed
  [1]




Undefined action reference
  $ cat > undef_action.fpp <<EOF
  > state machine M {
  >   state S
  >   initial do { a } enter S
  > }
  > EOF
  $ ofpp check undef_action.fpp
  ✗ undef_action.fpp:3:15: error in SM 'M': undefined action 'a'
  
  ✗ 1/1 file failed
  [1]




Undefined guard reference
  $ cat > undef_guard.fpp <<EOF
  > state machine M {
  >   state S
  >   initial enter C
  >   choice C { if g enter S else enter S }
  > }
  > EOF
  $ ofpp check undef_guard.fpp
  ✗ undef_guard.fpp:4:16: error in SM 'M': undefined guard 'g'
  
  ✗ 1/1 file failed
  [1]




Unreachable state
  $ cat > unreachable.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter S
  >   state S
  >   state T
  > }
  > EOF
  $ ofpp check unreachable.fpp
  ╭───┬─────────────────────┬────┬───────────────────────────────────────────────╮
  │   │ Location            │ SM │ Warning                                       │
  ├───┼─────────────────────┼────┼───────────────────────────────────────────────┤
  │ ! │ unreachable.fpp:4:8 │ M  │ signal 's' not handled in state 'S'           │
  │ ! │ unreachable.fpp:5:8 │ M  │ signal 's' not handled in state 'T'           │
  │ ! │ unreachable.fpp:2:9 │ M  │ unused signal 's'                             │
  │ ! │ unreachable.fpp:4:8 │ M  │ state 'S' has no outgoing transitions         │
  │   │                     │    │ (potential deadlock)                          │
  │ ! │ unreachable.fpp:5:8 │ M  │ state 'T' has no outgoing transitions         │
  │   │                     │    │ (potential deadlock)                          │
  ╰───┴─────────────────────┴────┴───────────────────────────────────────────────╯
  
  ✗ unreachable.fpp:5:8: error in SM 'M': unreachable state 'T'
  
  ✗ 1/1 file failed
  [1]




Choice cycle
  $ cat > cycle.fpp <<EOF
  > state machine M {
  >   guard g
  >   initial enter C1
  >   choice C1 { if g enter S else enter C2 }
  >   choice C2 { if g enter S else enter C1 }
  >   state S
  > }
  > EOF
  $ ofpp check cycle.fpp
  ✗ cycle.fpp:5:9: error in SM 'M': choice 'C2' is part of a cycle
  
  ✗ 1/1 file failed
  [1]




Duplicate signal transition
  $ cat > dup_sig.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter S
  >   state S {
  >     on s enter S
  >     on s enter S
  >   }
  > }
  > EOF
  $ ofpp check dup_sig.fpp
  ✗ dup_sig.fpp:6:7: error in SM 'M': duplicate transition on signal 's' in state 'S' (first at dup_sig.fpp:5:7)
  
  ✗ 1/1 file failed
  [1]




External state machine (no body) passes
  $ cat > external.fpp <<EOF
  > state machine M
  > EOF
  $ ofpp check external.fpp
  ✓ external.fpp

Empty state machine body requires initial
  $ cat > empty.fpp <<EOF
  > state machine M { }
  > EOF
  $ ofpp check empty.fpp
  ✗ empty.fpp:1:14: error in SM 'M': state machine has no initial transition
  
  ✗ 1/1 file failed
  [1]




Mix of valid and failing files
  $ ofpp check ok.fpp dup_action.fpp external.fpp
  ! dup_action.fpp:3:9: warning in SM 'M': unused action 'a'
  ✗ dup_action.fpp:1:14: error in SM '<tu>': duplicate definition 'M' (first defined at ok.fpp:1:14)
  ✗ external.fpp:1:14: error in SM '<tu>': duplicate definition 'M' (first defined at ok.fpp:1:14)
  ✗ dup_action.fpp:3:9: error in SM 'M': duplicate action 'a' (first defined at dup_action.fpp:2:9)
  ✗ dup_action.fpp:2:2: error in SM 'M': state machine has no initial transition
  
  ✗ 2/3 files failed
  [1]





Signal coverage warnings
  $ cat > coverage.fpp <<EOF
  > state machine M {
  >   signal s1
  >   signal s2
  >   initial enter S
  >   state S { on s1 enter T }
  >   state T
  > }
  > EOF
  $ ofpp check coverage.fpp
  ╭───┬──────────────────┬────┬──────────────────────────────────────────────────╮
  │   │ Location         │ SM │ Warning                                          │
  ├───┼──────────────────┼────┼──────────────────────────────────────────────────┤
  │ ! │ coverage.fpp:5:8 │ M  │ signal 's2' not handled in state 'S'             │
  │ ! │ coverage.fpp:6:8 │ M  │ signal 's1' not handled in state 'T'             │
  │ ! │ coverage.fpp:6:8 │ M  │ signal 's2' not handled in state 'T'             │
  │ ! │ coverage.fpp:3:9 │ M  │ unused signal 's2'                               │
  │ ! │ coverage.fpp:6:8 │ M  │ state 'T' has no outgoing transitions (potential │
  │   │                  │    │ deadlock)                                        │
  ╰───┴──────────────────┴────┴──────────────────────────────────────────────────╯
  
  ✓ coverage.fpp


Signal coverage with inherited handlers
  $ cat > inherited.fpp <<EOF
  > state machine M {
  >   signal s1
  >   initial enter P
  >   state P {
  >     on s1 enter P
  >     initial enter C
  >     state C
  >   }
  > }
  > EOF
  $ ofpp check inherited.fpp
  ✓ inherited.fpp

Signal coverage warnings don't affect exit code
  $ ofpp check coverage.fpp; echo "exit=$?"
  ╭───┬──────────────────┬────┬──────────────────────────────────────────────────╮
  │   │ Location         │ SM │ Warning                                          │
  ├───┼──────────────────┼────┼──────────────────────────────────────────────────┤
  │ ! │ coverage.fpp:5:8 │ M  │ signal 's2' not handled in state 'S'             │
  │ ! │ coverage.fpp:6:8 │ M  │ signal 's1' not handled in state 'T'             │
  │ ! │ coverage.fpp:6:8 │ M  │ signal 's2' not handled in state 'T'             │
  │ ! │ coverage.fpp:3:9 │ M  │ unused signal 's2'                               │
  │ ! │ coverage.fpp:6:8 │ M  │ state 'T' has no outgoing transitions (potential │
  │   │                  │    │ deadlock)                                        │
  ╰───┴──────────────────┴────┴──────────────────────────────────────────────────╯
  
  ✓ coverage.fpp
  exit=0


Liveness: cycle with no exit
  $ cat > livelock.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter C
  >   state C { on s enter A }
  >   state A { on s enter B }
  >   state B { on s enter A }
  > }
  > EOF
  $ ofpp check livelock.fpp
  ! livelock.fpp:5:8: warning in SM 'M': states {'A', 'B'} form a cycle with no exit
  ✓ livelock.fpp

Liveness: cycle with exit (no warning)
  $ cat > cycle_exit.fpp <<EOF
  > state machine M {
  >   signal s1
  >   signal s2
  >   initial enter A
  >   state A { on s1 enter B on s2 enter C }
  >   state B { on s1 enter A on s2 enter C }
  >   state C
  > }
  > EOF
  $ ofpp check cycle_exit.fpp
  ╭───┬────────────────────┬────┬────────────────────────────────────────────────╮
  │   │ Location           │ SM │ Warning                                        │
  ├───┼────────────────────┼────┼────────────────────────────────────────────────┤
  │ ! │ cycle_exit.fpp:7:8 │ M  │ signal 's1' not handled in state 'C'           │
  │ ! │ cycle_exit.fpp:7:8 │ M  │ signal 's2' not handled in state 'C'           │
  │ ! │ cycle_exit.fpp:7:8 │ M  │ state 'C' has no outgoing transitions          │
  │   │                    │    │ (potential deadlock)                           │
  ╰───┴────────────────────┴────┴────────────────────────────────────────────────╯
  
  ✓ cycle_exit.fpp


Liveness: three-state cycle
  $ cat > tri_cycle.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter A
  >   state A { on s enter B }
  >   state B { on s enter C }
  >   state C { on s enter A }
  > }
  > EOF
  $ ofpp check tri_cycle.fpp
  ! tri_cycle.fpp:4:8: warning in SM 'M': states {'A', 'B', 'C'} form a cycle with no exit
  ✓ tri_cycle.fpp

Unused declarations
  $ cat > unused.fpp <<EOF
  > state machine M {
  >   action doStuff
  >   action unused_action
  >   guard isReady
  >   signal go
  >   signal stale_signal
  >   initial enter C
  >   choice C { if isReady do { doStuff } enter S else enter S }
  >   state S { on go enter S }
  > }
  > EOF
  $ ofpp check unused.fpp
  ╭───┬────────────────┬────┬────────────────────────────────────────────────╮
  │   │ Location       │ SM │ Warning                                        │
  ├───┼────────────────┼────┼────────────────────────────────────────────────┤
  │ ! │ unused.fpp:9:8 │ M  │ signal 'stale_signal' not handled in state 'S' │
  │ ! │ unused.fpp:3:9 │ M  │ unused action 'unused_action'                  │
  │ ! │ unused.fpp:6:9 │ M  │ unused signal 'stale_signal'                   │
  ╰───┴────────────────┴────┴────────────────────────────────────────────────╯
  
  ✓ unused.fpp



Transition shadowing
  $ cat > shadow.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter P
  >   state P {
  >     on s enter P
  >     initial enter C
  >     state C { on s enter C }
  >   }
  > }
  > EOF
  $ ofpp check shadow.fpp
  ! shadow.fpp:7:10: warning in SM 'M': state 'C' shadows parent handler for signal 's'
  ✓ shadow.fpp


Deadlock: sink state with no transitions
  $ cat > sink.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter A
  >   state A { on s enter B }
  >   state B
  > }
  > EOF
  $ ofpp check sink.fpp
  ╭───┬──────────────┬────┬──────────────────────────────────────────────────────╮
  │   │ Location     │ SM │ Warning                                              │
  ├───┼──────────────┼────┼──────────────────────────────────────────────────────┤
  │ ! │ sink.fpp:5:8 │ M  │ signal 's' not handled in state 'B'                  │
  │ ! │ sink.fpp:5:8 │ M  │ state 'B' has no outgoing transitions (potential     │
  │   │              │    │ deadlock)                                            │
  ╰───┴──────────────┴────┴──────────────────────────────────────────────────────╯
  
  ✓ sink.fpp



Deadlock: inherited handler prevents warning
  $ cat > no_deadlock.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter P
  >   state P {
  >     on s enter P
  >     initial enter C
  >     state C
  >   }
  > }
  > EOF
  $ ofpp check no_deadlock.fpp
  ✓ no_deadlock.fpp

Guard completeness: choice without else
  $ cat > no_else.fpp <<EOF
  > state machine M {
  >   guard g
  >   initial enter C
  >   state S
  >   choice C { if g enter S }
  > }
  > EOF
  $ ofpp check no_else.fpp
  ! no_else.fpp:5:9: warning in SM 'M': choice 'C' has no else branch (may fail to transition)
  ✓ no_else.fpp

Guard completeness: choice with else (no warning)
  $ cat > with_else.fpp <<EOF
  > state machine M {
  >   guard g
  >   initial enter C
  >   state S
  >   choice C { if g enter S else enter S }
  > }
  > EOF
  $ ofpp check with_else.fpp
  ✓ with_else.fpp

Contextual hints for undefined references
  $ cat > hint.fpp <<EOF
  > state machine M {
  >   guard myGuard
  >   initial do { myGuard } enter S
  >   state S
  > }
  > EOF
  $ ofpp check hint.fpp
  ! hint.fpp:2:8: warning in SM 'M': unused guard 'myGuard'
  ✗ hint.fpp:3:15: error in SM 'M': undefined action 'myGuard' (a guard 'myGuard' exists)
  
  ✗ 1/1 file failed
  [1]


Disable coverage with --warning
  $ ofpp check --warning=-cov coverage.fpp
  ╭───┬──────────────────┬────┬──────────────────────────────────────────────────╮
  │   │ Location         │ SM │ Warning                                          │
  ├───┼──────────────────┼────┼──────────────────────────────────────────────────┤
  │ ! │ coverage.fpp:3:9 │ M  │ unused signal 's2'                               │
  │ ! │ coverage.fpp:6:8 │ M  │ state 'T' has no outgoing transitions (potential │
  │   │                  │    │ deadlock)                                        │
  ╰───┴──────────────────┴────┴──────────────────────────────────────────────────╯
  
  ✓ coverage.fpp


Disable all warnings with --warning
  $ ofpp check --warning=-all coverage.fpp
  ✓ coverage.fpp

Only enable deadlock with --warning
  $ ofpp check --warning=-all,+dea coverage.fpp
  ! coverage.fpp:6:8: warning in SM 'M': state 'T' has no outgoing transitions (potential deadlock)
  ✓ coverage.fpp

Promote all warnings to errors with --error
  $ ofpp check --error=all livelock.fpp
  ✗ livelock.fpp:5:8: error in SM 'M': states {'A', 'B'} form a cycle with no exit
  
  ✗ 1/1 file failed
  [1]


Promote specific analysis to error
  $ cat > sink2.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter A
  >   state A { on s enter B }
  >   state B
  > }
  > EOF
  $ ofpp check --warning=-cov --error=dea sink2.fpp
  ✗ sink2.fpp:5:8: error in SM 'M': state 'B' has no outgoing transitions (potential deadlock)
  
  ✗ 1/1 file failed
  [1]


Disabled analysis not promoted by --error (deadlock stays off)
  $ ofpp check --warning=-dea --error=all coverage.fpp
  ✗ coverage.fpp:5:8: error in SM 'M': signal 's2' not handled in state 'S'
  ✗ coverage.fpp:6:8: error in SM 'M': signal 's1' not handled in state 'T'
  ✗ coverage.fpp:6:8: error in SM 'M': signal 's2' not handled in state 'T'
  ✗ coverage.fpp:3:9: error in SM 'M': unused signal 's2'
  
  ✗ 1/1 file failed
  [1]


Unknown analysis in spec
  $ ofpp check -w bogus ok.fpp 2>&1
  ofpp: option '-w': unknown analysis 'bogus'
  Usage: ofpp check [--error=SPEC] [--verbose] [--warning=SPEC] [OPTION]… FILE…
  Try 'ofpp check --help' or 'ofpp --help' for more information.
  [1]

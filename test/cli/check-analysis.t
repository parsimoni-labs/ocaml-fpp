Valid state machine passes
  $ cat > ok.fpp <<EOF
  > state machine M {
  >   action a
  >   guard g
  >   signal s
  >   state S { on s enter S }
  >   initial enter S
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
  ✓ ok.fpp
  ✗ dup_action.fpp:3:9: error in SM 'M': duplicate action 'a' (first defined at dup_action.fpp:2:9)
  ✗ dup_action.fpp:2:2: error in SM 'M': state machine has no initial transition
  ✓ external.fpp
  
  ✗ 1/3 files failed
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
  ⚠ coverage.fpp:5:8: warning in SM 'M': signal 's2' not handled in state 'S'
  ⚠ coverage.fpp:6:8: warning in SM 'M': signal 's1' not handled in state 'T'
  ⚠ coverage.fpp:6:8: warning in SM 'M': signal 's2' not handled in state 'T'
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
  ⚠ coverage.fpp:5:8: warning in SM 'M': signal 's2' not handled in state 'S'
  ⚠ coverage.fpp:6:8: warning in SM 'M': signal 's1' not handled in state 'T'
  ⚠ coverage.fpp:6:8: warning in SM 'M': signal 's2' not handled in state 'T'
  ✓ coverage.fpp
  exit=0

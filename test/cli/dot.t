Basic state machine with self-transition
  $ cat > simple.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter S
  >   state S { on s enter S }
  > }
  > EOF
  $ ofpp dot simple.fpp
  digraph M {
    rankdir=TB
    fontname="Helvetica"
    node [fontname="Helvetica" fontsize=11]
    edge [fontname="Helvetica" fontsize=10]
    __init__ [shape=point width=0.25]
    __init__ -> S [style=dashed label=""]
    S [label="S" shape=Mrecord]
    S -> S [label="s"]
  }

Choice with guard and else
  $ cat > choice.fpp <<EOF
  > state machine M {
  >   guard g
  >   initial enter C
  >   state S
  >   choice C { if g enter S else enter S }
  > }
  > EOF
  $ ofpp dot choice.fpp
  digraph M {
    rankdir=TB
    fontname="Helvetica"
    node [fontname="Helvetica" fontsize=11]
    edge [fontname="Helvetica" fontsize=10]
    __init__ [shape=point width=0.25]
    __init__ -> C [style=dashed label=""]
    S [label="S" shape=Mrecord]
    C [label="C" shape=diamond]
    C -> S [label="[g]"]
    C -> S [label="else"]
  }

Hierarchical state machine with cluster subgraph
  $ cat > hier.fpp <<EOF
  > state machine M {
  >   signal s1
  >   signal s2
  >   initial enter P
  >   state P {
  >     on s1 enter P
  >     initial enter A
  >     state A { on s2 enter B }
  >     state B
  >   }
  > }
  > EOF
  $ ofpp dot hier.fpp
  digraph M {
    rankdir=TB
    fontname="Helvetica"
    node [fontname="Helvetica" fontsize=11]
    edge [fontname="Helvetica" fontsize=10]
    __init__ [shape=point width=0.25]
    __init__ -> P [style=dashed label=""]
    subgraph cluster_P {
      label="P"
      style=rounded
      __init_P__ [shape=point width=0.2]
      __init_P__ -> P_A [style=dashed label=""]
      P_A [label="A" shape=Mrecord]
      P_A -> P_B [label="s2"]
      P_B [label="B" shape=Mrecord]
    }
    P -> P [label="s1"]
  }

Entry and exit actions in state labels
  $ cat > actions.fpp <<EOF
  > state machine M {
  >   action a1
  >   action a2
  >   signal s
  >   initial enter S
  >   state S {
  >     entry do { a1 }
  >     exit do { a2 }
  >     on s enter S
  >   }
  > }
  > EOF
  $ ofpp dot actions.fpp
  digraph M {
    rankdir=TB
    fontname="Helvetica"
    node [fontname="Helvetica" fontsize=11]
    edge [fontname="Helvetica" fontsize=10]
    __init__ [shape=point width=0.25]
    __init__ -> S [style=dashed label=""]
    S [label="S\nentry / a1\nexit / a2" shape=Mrecord]
    S -> S [label="s"]
  }

External state machine (no body) produces no output
  $ cat > ext.fpp <<EOF
  > state machine M
  > EOF
  $ ofpp dot ext.fpp

D2 format output
  $ ofpp dot -f d2 simple.fpp
  M: {label: M}
  direction: down
  (***) -> S: {style.stroke-dash: 3}
  S: S
  S -> S: s

D2 hierarchical state machine
  $ ofpp dot -f d2 hier.fpp
  M: {label: M}
  direction: down
  (***) -> P: {style.stroke-dash: 3}
  P: P {
    P.A: A
    P.A -> P.B: s2
    P.B: B
  }
  P -> P.A: {style.stroke-dash: 3}
  P -> P: s1

D2 choice with guard
  $ ofpp dot -f d2 choice.fpp
  M: {label: M}
  direction: down
  (***) -> C: {style.stroke-dash: 3}
  S: S
  C: C {shape: diamond}
  C -> S: [g]
  C -> S: else

Filter by SM name
  $ cat > multi.fpp <<EOF
  > state machine A {
  >   initial enter S
  >   state S
  > }
  > state machine B {
  >   initial enter T
  >   state T
  > }
  > EOF
  $ ofpp dot --sm B multi.fpp
  digraph B {
    rankdir=TB
    fontname="Helvetica"
    node [fontname="Helvetica" fontsize=11]
    edge [fontname="Helvetica" fontsize=10]
    __init__ [shape=point width=0.25]
    __init__ -> T [style=dashed label=""]
    T [label="T" shape=Mrecord]
  }

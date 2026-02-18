Basic state machine (D2 to stdout)
  $ cat > simple.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter S
  >   state S { on s enter S }
  > }
  > EOF
  $ ofpp dot simple.fpp
  vars: {
    d2-config: {
      layout-engine: elk
    }
  }
  classes: {
    state: {
      style.border-radius: 8
      style.fill: "#e8f0fe"
      style.stroke: "#4285f4"
      style.font-color: "#1a1a2e"
    }
    choice: {
      shape: diamond
      style.fill: "#fff8e1"
      style.stroke: "#f9ab00"
      style.font-color: "#1a1a2e"
    }
  }
  # M
  direction: down
  __init__: "" { shape: circle; width: 20; height: 20; style.fill: "#1a1a2e"; style.stroke: "#1a1a2e" }
  S: S { class: state }
  __init__ -> S
  S -> S: s

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
  vars: {
    d2-config: {
      layout-engine: elk
    }
  }
  classes: {
    state: {
      style.border-radius: 8
      style.fill: "#e8f0fe"
      style.stroke: "#4285f4"
      style.font-color: "#1a1a2e"
    }
    choice: {
      shape: diamond
      style.fill: "#fff8e1"
      style.stroke: "#f9ab00"
      style.font-color: "#1a1a2e"
    }
  }
  # M
  direction: down
  __init__: "" { shape: circle; width: 20; height: 20; style.fill: "#1a1a2e"; style.stroke: "#1a1a2e" }
  S: S { class: state }
  C: C { class: choice }
  __init__ -> C
  C -> S: "[g]"
  C -> S: else

Hierarchical state machine
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
  vars: {
    d2-config: {
      layout-engine: elk
    }
  }
  classes: {
    state: {
      style.border-radius: 8
      style.fill: "#e8f0fe"
      style.stroke: "#4285f4"
      style.font-color: "#1a1a2e"
    }
    choice: {
      shape: diamond
      style.fill: "#fff8e1"
      style.stroke: "#f9ab00"
      style.font-color: "#1a1a2e"
    }
  }
  # M
  direction: down
  __init__: "" { shape: circle; width: 20; height: 20; style.fill: "#1a1a2e"; style.stroke: "#1a1a2e" }
  P: P {
    style.border-radius: 8
    style.fill: "#f8f9fa"
    style.stroke: "#5f6368"
    A: A { class: state }
    B: B { class: state }
    __init__: "" { shape: circle; width: 12; height: 12; style.fill: "#1a1a2e"; style.stroke: "#1a1a2e" }
  }
  __init__ -> P
  P.A -> P.B: s2
  P.__init__ -> P.A
  P -> P: s1

External state machine (no body) produces no output
  $ cat > ext.fpp <<EOF
  > state machine M
  > EOF
  $ ofpp dot ext.fpp

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
  vars: {
    d2-config: {
      layout-engine: elk
    }
  }
  classes: {
    state: {
      style.border-radius: 8
      style.fill: "#e8f0fe"
      style.stroke: "#4285f4"
      style.font-color: "#1a1a2e"
    }
    choice: {
      shape: diamond
      style.fill: "#fff8e1"
      style.stroke: "#f9ab00"
      style.font-color: "#1a1a2e"
    }
  }
  # B
  direction: down
  __init__: "" { shape: circle; width: 20; height: 20; style.fill: "#1a1a2e"; style.stroke: "#1a1a2e" }
  T: T { class: state }
  __init__ -> T

Structured edge labels with guard and actions
  $ cat > guarded.fpp <<EOF
  > state machine M {
  >   action a1
  >   action a2
  >   guard g
  >   signal s
  >   initial enter S1
  >   state S1 { on s if g do { a1, a2 } enter S2 }
  >   state S2 { on s do { a1 } enter S1 }
  > }
  > EOF
  $ ofpp dot guarded.fpp
  vars: {
    d2-config: {
      layout-engine: elk
    }
  }
  classes: {
    state: {
      style.border-radius: 8
      style.fill: "#e8f0fe"
      style.stroke: "#4285f4"
      style.font-color: "#1a1a2e"
    }
    choice: {
      shape: diamond
      style.fill: "#fff8e1"
      style.stroke: "#f9ab00"
      style.font-color: "#1a1a2e"
    }
  }
  # M
  direction: down
  __init__: "" { shape: circle; width: 20; height: 20; style.fill: "#1a1a2e"; style.stroke: "#1a1a2e" }
  S1: S1 { class: state }
  S2: S2 { class: state }
  __init__ -> S1
  S1 -> S2: s {
    source-arrowhead.label: [g]
    target-arrowhead.label: / a1, a2
  }
  S2 -> S1: s {
    target-arrowhead.label: / a1
  }

Render to PNG via -o
  $ ofpp dot -o sm.png simple.fpp
  $ test -f sm.png && echo "PNG created"
  PNG created

Render to SVG via -o
  $ ofpp dot -o sm.svg simple.fpp
  $ test -f sm.svg && echo "SVG created"
  SVG created

D2 output compiles for all upstream state machines
  $ for f in "$TESTDIR"/../upstream/state_machine/*.fpp; do
  >   d2out=$(ofpp dot "$f" 2>/dev/null)
  >   if [ -n "$d2out" ]; then
  >     echo "$d2out" | d2 - /dev/null 2>/dev/null || echo "FAIL: $(basename $f)"
  >   fi
  > done

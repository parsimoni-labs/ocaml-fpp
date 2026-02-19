Basic state machine (DOT to stdout)
  $ cat > simple.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter S
  >   state S { on s enter S }
  > }
  > EOF
  $ ofpp dot simple.fpp
  digraph "M" {
    compound=true;
    rankdir=TB;
    bgcolor=white;
    pad="0.4";
    node [fontname="Helvetica" fontsize=11];
    edge [fontname="Helvetica" fontsize=9 color="#5f6368"];
    "__init__" [shape=circle width=0.25 fixedsize=true style=filled fillcolor="#1a1a2e" label=""];
    "S" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="S"];
    "__init__" -> "S";
    "S" -> "S" [label="s"];
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
  digraph "M" {
    compound=true;
    rankdir=TB;
    bgcolor=white;
    pad="0.4";
    node [fontname="Helvetica" fontsize=11];
    edge [fontname="Helvetica" fontsize=9 color="#5f6368"];
    "__init__" [shape=circle width=0.25 fixedsize=true style=filled fillcolor="#1a1a2e" label=""];
    "S" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="S"];
    "C" [shape=diamond style=filled fillcolor="#fff8e1" color="#f9ab00" label="C"];
    "__init__" -> "C";
    "C" -> "S" [label="[g]"];
    "C" -> "S" [label="else"];
  }

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
  digraph "M" {
    compound=true;
    rankdir=TB;
    bgcolor=white;
    pad="0.4";
    node [fontname="Helvetica" fontsize=11];
    edge [fontname="Helvetica" fontsize=9 color="#5f6368"];
    "__init__" [shape=circle width=0.25 fixedsize=true style=filled fillcolor="#1a1a2e" label=""];
    subgraph "cluster_P" {
      label="P";
      style="rounded,filled";
      fillcolor="#f8f9fa";
      color="#5f6368";
      fontname="Helvetica";
      "P.A" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="A"];
      "P.B" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="B"];
      "P.__init__" [shape=circle width=0.25 fixedsize=true style=filled fillcolor="#1a1a2e" label=""];
    }
    "__init__" -> "P";
    "P.A" -> "P.B" [label="s2"];
    "P.__init__" -> "P.A";
    "P" -> "P" [label="s1"];
  }

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
  digraph "B" {
    compound=true;
    rankdir=TB;
    bgcolor=white;
    pad="0.4";
    node [fontname="Helvetica" fontsize=11];
    edge [fontname="Helvetica" fontsize=9 color="#5f6368"];
    "__init__" [shape=circle width=0.25 fixedsize=true style=filled fillcolor="#1a1a2e" label=""];
    "T" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="T"];
    "__init__" -> "T";
  }

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
  digraph "M" {
    compound=true;
    rankdir=TB;
    bgcolor=white;
    pad="0.4";
    node [fontname="Helvetica" fontsize=11];
    edge [fontname="Helvetica" fontsize=9 color="#5f6368"];
    "__init__" [shape=circle width=0.25 fixedsize=true style=filled fillcolor="#1a1a2e" label=""];
    "S1" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="S1"];
    "S2" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="S2"];
    "__init__" -> "S1";
    "S1" -> "S2" [label="s [g]\n/ a1, a2"];
    "S2" -> "S1" [label="s\n/ a1"];
  }

Render to PNG via -o
  $ ofpp dot -o sm.png simple.fpp
  $ test -f sm.png && echo "PNG created"
  PNG created

Render to SVG via -o
  $ ofpp dot -o sm.svg simple.fpp
  $ test -f sm.svg && echo "SVG created"
  SVG created

DOT output compiles for all upstream state machines
  $ for f in "$TESTDIR"/../upstream/state_machine/*.fpp; do
  >   dotout=$(ofpp dot "$f" 2>/dev/null)
  >   if [ -n "$dotout" ]; then
  >     echo "$dotout" | dot -Tsvg -o /dev/null 2>/dev/null || echo "FAIL: $(basename $f)"
  >   fi
  > done

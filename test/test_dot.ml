(** Tests for {!Fpp.Dot}: state machine to Graphviz DOT rendering. *)

let parse s =
  match Fpp.parse_string s with
  | tu -> tu
  | exception Fpp.Parse_error e ->
      Alcotest.failf "parse error: %a" Fpp.pp_error e

let render s =
  let tu = parse s in
  let sms = Fpp.state_machines tu in
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  List.iter (fun sm -> Fpp.Dot.pp ppf sm) sms;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

let contains ~substr s =
  let len = String.length substr in
  let slen = String.length s in
  if len > slen then false
  else
    let found = ref false in
    for i = 0 to slen - len do
      if String.sub s i len = substr then found := true
    done;
    !found

(* ── Basic rendering ───────────────────────────────────────────────── *)

let test_basic_sm () =
  let dot =
    render
      {|
    state machine M {
      signal s
      initial enter S
      state S { on s enter S }
    }
  |}
  in
  Alcotest.(check bool)
    "digraph header" true
    (contains ~substr:{|digraph "M"|} dot);
  Alcotest.(check bool)
    "compound=true" true
    (contains ~substr:"compound=true" dot);
  Alcotest.(check bool) "state node" true (contains ~substr:{|shape=box|} dot);
  Alcotest.(check bool) "init node" true (contains ~substr:{|"__init__"|} dot);
  Alcotest.(check bool)
    "self-loop edge" true
    (contains ~substr:{|"S" -> "S"|} dot)

let test_external_sm () =
  let dot = render {| state machine M |} in
  Alcotest.(check string) "empty output" "" dot

let test_choice_node () =
  let dot =
    render
      {|
    state machine M {
      guard g
      initial enter C
      state S
      choice C { if g enter S else enter S }
    }
  |}
  in
  Alcotest.(check bool)
    "choice diamond" true
    (contains ~substr:"shape=diamond" dot);
  Alcotest.(check bool) "guard label" true (contains ~substr:{|[ g ]|} dot);
  Alcotest.(check bool) "else label" true (contains ~substr:{|<b>else</b>|} dot)

let test_hierarchical () =
  let dot =
    render
      {|
    state machine M {
      signal s
      initial enter P
      state P {
        on s enter P
        initial enter A
        state A
      }
    }
  |}
  in
  Alcotest.(check bool)
    "subgraph cluster" true
    (contains ~substr:{|subgraph "cluster_P"|} dot);
  Alcotest.(check bool) "child state" true (contains ~substr:{|"P.A"|} dot);
  Alcotest.(check bool)
    "nested init" true
    (contains ~substr:{|"P.__init__"|} dot)

let test_entry_exit_actions () =
  let dot =
    render
      {|
    state machine M {
      action a1
      action a2
      signal s
      initial enter S
      state S {
        entry do { a1 }
        exit do { a2 }
        on s enter S
      }
    }
  |}
  in
  Alcotest.(check bool) "HTML table label" true (contains ~substr:"<table" dot);
  Alcotest.(check bool)
    "entry action" true
    (contains ~substr:"<b>entry</b> / a1" dot);
  Alcotest.(check bool)
    "exit action" true
    (contains ~substr:"<b>exit</b> / a2" dot)

let test_structured_labels () =
  let dot =
    render
      {|
    state machine M {
      action a1
      action a2
      guard g
      signal s
      initial enter S1
      state S1 {
        on s if g do { a1, a2 } enter S2
      }
      state S2 {
        on s do { a1 } enter S1
        on s enter S2
      }
    }
  |}
  in
  Alcotest.(check bool)
    "label node for cross-edge" true
    (contains ~substr:"__e0" dot);
  Alcotest.(check bool) "guard in label" true (contains ~substr:{|[ g ]|} dot);
  Alcotest.(check bool)
    "actions in label" true
    (contains ~substr:"/ a1, a2" dot);
  Alcotest.(check bool)
    "self-loop with inline label" true
    (contains ~substr:{|"S2" -> "S2" [label=<<b>s</b>>]|} dot);
  Alcotest.(check bool)
    "label node to target" true
    (contains ~substr:{|"__e0" -> "S2"|} dot)

let test_choice_with_actions () =
  let dot =
    render
      {|
    state machine M {
      action a1
      guard g
      initial enter C
      state S
      choice C { if g do { a1 } enter S else enter S }
    }
  |}
  in
  Alcotest.(check bool)
    "choice diamond" true
    (contains ~substr:"shape=diamond" dot);
  Alcotest.(check bool)
    "guard in edge label" true
    (contains ~substr:{|[ g ]|} dot);
  Alcotest.(check bool)
    "action in choice edge" true
    (contains ~substr:"/ a1" dot);
  Alcotest.(check bool)
    "label node for choice edge" true
    (contains ~substr:"__e0" dot)

(* ── Topology rendering ────────────────────────────────────────────── *)

let render_topology s =
  let tu = parse s in
  let topos = Fpp.topologies tu in
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  List.iter (fun topo -> Fpp.Dot.pp_topology tu ppf topo) topos;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

let basic_topology_fpp =
  {|
  port Data
  active component Sender { output port out: Data }
  passive component Receiver { sync input port inp: Data }
  instance s: Sender base id 0x100
  instance r: Receiver base id 0x200
  topology T {
    instance s
    instance r
    connections C { s.out -> r.inp }
  }
|}

let test_basic_topology () =
  let dot = render_topology basic_topology_fpp in
  Alcotest.(check bool)
    "digraph header" true
    (contains ~substr:{|digraph "T"|} dot);
  Alcotest.(check bool) "rankdir=LR" true (contains ~substr:"rankdir=LR" dot);
  Alcotest.(check bool) "sender node" true (contains ~substr:{|"s"|} dot);
  Alcotest.(check bool) "receiver node" true (contains ~substr:{|"r"|} dot);
  Alcotest.(check bool) "edge exists" true (contains ~substr:{|"s" -> "r"|} dot)

let test_topology_component_colors () =
  let dot = render_topology basic_topology_fpp in
  (* Active component: green fill *)
  Alcotest.(check bool)
    "active green fill" true
    (contains ~substr:{|fillcolor="#dcedc8"|} dot);
  (* Passive component: blue fill *)
  Alcotest.(check bool)
    "passive blue fill" true
    (contains ~substr:{|fillcolor="#e8f0fe"|} dot)

let test_topology_edge_labels () =
  let dot = render_topology basic_topology_fpp in
  Alcotest.(check bool)
    "port names in edge" true
    (contains ~substr:{|out → inp|} dot)

let test_topology_with_import () =
  let dot =
    render_topology
      {|
    port Data
    active component A { output port out: Data }
    passive component B { sync input port inp: Data }
    instance a1: A base id 0x100
    instance b1: B base id 0x200
    instance a2: A base id 0x300
    topology Sub {
      public instance a1
      public instance b1
      connections C { a1.out -> b1.inp }
    }
    topology Main {
      import Sub
      instance a2
      connections C { a2.out -> b1.inp }
    }
  |}
  in
  Alcotest.(check bool)
    "import cluster" true
    (contains ~substr:{|subgraph "cluster_Sub"|} dot)

(* ── Suite ──────────────────────────────────────────────────────────── *)

let suite =
  ( "dot",
    [
      Alcotest.test_case "basic_sm" `Quick test_basic_sm;
      Alcotest.test_case "external_sm" `Quick test_external_sm;
      Alcotest.test_case "choice_node" `Quick test_choice_node;
      Alcotest.test_case "hierarchical" `Quick test_hierarchical;
      Alcotest.test_case "entry_exit_actions" `Quick test_entry_exit_actions;
      Alcotest.test_case "structured_labels" `Quick test_structured_labels;
      Alcotest.test_case "choice_with_actions" `Quick test_choice_with_actions;
      Alcotest.test_case "basic_topology" `Quick test_basic_topology;
      Alcotest.test_case "topology_colors" `Quick test_topology_component_colors;
      Alcotest.test_case "topology_edge_labels" `Quick test_topology_edge_labels;
      Alcotest.test_case "topology_import" `Quick test_topology_with_import;
    ] )

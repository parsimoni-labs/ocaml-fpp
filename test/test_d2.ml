(** Tests for {!Fpp.D2}: state machine to D2 rendering. *)

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
  List.iter (fun sm -> Fpp.D2.pp ppf sm) sms;
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
  let d2 =
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
    "contains preamble" true
    (contains ~substr:"layout-engine: elk" d2);
  Alcotest.(check bool) "contains SM name" true (contains ~substr:"# M" d2);
  Alcotest.(check bool) "contains state" true (contains ~substr:"S: S" d2);
  Alcotest.(check bool)
    "contains init node" true
    (contains ~substr:"__init__" d2);
  Alcotest.(check bool) "contains edge" true (contains ~substr:"S -> S: s" d2)

let test_external_sm () =
  let d2 = render {| state machine M |} in
  Alcotest.(check string) "empty output" "" d2

let test_choice_node () =
  let d2 =
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
    "choice class" true
    (contains ~substr:"class: choice" d2);
  Alcotest.(check bool) "guard label" true (contains ~substr:"[g]" d2);
  Alcotest.(check bool) "else branch" true (contains ~substr:"else" d2)

let test_hierarchical () =
  let d2 =
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
  Alcotest.(check bool) "container open" true (contains ~substr:"P: P {" d2);
  Alcotest.(check bool) "child state" true (contains ~substr:"A: A" d2);
  Alcotest.(check bool) "nested init" true (contains ~substr:"P.__init__" d2)

let test_entry_exit_actions () =
  let d2 =
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
  Alcotest.(check bool) "entry action" true (contains ~substr:"entry / a1" d2);
  Alcotest.(check bool) "exit action" true (contains ~substr:"exit / a2" d2)

(* ── Suite ──────────────────────────────────────────────────────────── *)

let suite =
  ( "d2",
    [
      Alcotest.test_case "basic_sm" `Quick test_basic_sm;
      Alcotest.test_case "external_sm" `Quick test_external_sm;
      Alcotest.test_case "choice_node" `Quick test_choice_node;
      Alcotest.test_case "hierarchical" `Quick test_hierarchical;
      Alcotest.test_case "entry_exit_actions" `Quick test_entry_exit_actions;
    ] )

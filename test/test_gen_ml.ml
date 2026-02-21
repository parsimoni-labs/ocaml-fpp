(** Tests for {!Fpp.Gen_ml}: state machine to OCaml code generation. *)

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
  List.iter (fun sm -> Fpp.Gen_ml.pp ppf sm) sms;
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

(* ── Basic generation ─────────────────────────────────────────────── *)

let test_simple_sm () =
  let ml =
    render
      {|
    state machine M {
      signal s
      initial enter S1
      state S1 { on s enter S2 }
      state S2
    }
  |}
  in
  Alcotest.(check bool) "phantom types" true (contains ~substr:"type s1" ml);
  Alcotest.(check bool) "state GADT" true (contains ~substr:"_ state =" ml);
  Alcotest.(check bool)
    "existential" true
    (contains ~substr:"type any = State" ml);
  Alcotest.(check bool) "module Make" true (contains ~substr:"module Make" ml);
  Alcotest.(check bool) "let create" true (contains ~substr:"let create" ml);
  Alcotest.(check bool) "let step" true (contains ~substr:"let step" ml)

let test_typed_signal () =
  let ml =
    render
      {|
    state machine M {
      signal s : U32
      initial enter S
      state S { on s enter S }
    }
  |}
  in
  Alcotest.(check bool) "signal type" true (contains ~substr:"type signal" ml);
  Alcotest.(check bool)
    "signal with data" true
    (contains ~substr:"S of int32" ml)

let test_guard_choice () =
  let ml =
    render
      {|
    state machine M {
      action a1
      guard g
      signal s
      initial enter C
      state S
      choice C { if g do { a1 } enter S else enter S }
    }
  |}
  in
  Alcotest.(check bool)
    "ACTIONS module type" true
    (contains ~substr:"ACTIONS" ml);
  Alcotest.(check bool) "GUARDS module type" true (contains ~substr:"GUARDS" ml);
  Alcotest.(check bool) "enter_c function" true (contains ~substr:"enter_c" ml)

let test_nested_state () =
  let ml =
    render
      {|
    state machine M {
      initial enter S
      state S {
        initial enter T
        state T
      }
    }
  |}
  in
  Alcotest.(check bool) "leaf phantom type" true (contains ~substr:"type t" ml);
  Alcotest.(check bool)
    "leaf state GADT" true
    (contains ~substr:"| T : t state" ml);
  Alcotest.(check bool)
    "create resolves to leaf" true
    (contains ~substr:"State T" ml)

let test_door () =
  let ml =
    render
      {|
    state machine Door {
      action lock
      guard locked
      signal open
      signal close
      initial enter Closed
      state Closed { on open if locked enter Closed
                     on open enter Opened }
      state Opened { on close do { lock } enter Closed }
    }
  |}
  in
  Alcotest.(check bool)
    "phantom closed" true
    (contains ~substr:"type closed" ml);
  Alcotest.(check bool)
    "phantom opened" true
    (contains ~substr:"type opened" ml);
  Alcotest.(check bool) "State Closed" true (contains ~substr:"State Closed" ml);
  Alcotest.(check bool) "State Opened" true (contains ~substr:"State Opened" ml);
  Alcotest.(check bool) "G.locked" true (contains ~substr:"G.locked" ml);
  Alcotest.(check bool) "A.lock" true (contains ~substr:"A.lock" ml)

(* ── Suite ──────────────────────────────────────────────────────────── *)

let suite =
  ( "gen_ml",
    [
      Alcotest.test_case "simple_sm" `Quick test_simple_sm;
      Alcotest.test_case "typed_signal" `Quick test_typed_signal;
      Alcotest.test_case "guard_choice" `Quick test_guard_choice;
      Alcotest.test_case "nested_state" `Quick test_nested_state;
      Alcotest.test_case "door" `Quick test_door;
    ] )

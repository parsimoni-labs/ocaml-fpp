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
  Alcotest.(check bool) "state type" true (contains ~substr:"type state =" ml);
  Alcotest.(check bool) "module Make" true (contains ~substr:"module Make" ml);
  Alcotest.(check bool) "let create" true (contains ~substr:"let create" ml)

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
  Alcotest.(check bool) "signal GADT" true (contains ~substr:"signal" ml);
  Alcotest.(check bool) "event type" true (contains ~substr:"event" ml)

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
  Alcotest.(check bool) "GUARDS module type" true (contains ~substr:"GUARDS" ml)

(* ── Suite ──────────────────────────────────────────────────────────── *)

let suite =
  ( "gen_ml",
    [
      Alcotest.test_case "simple_sm" `Quick test_simple_sm;
      Alcotest.test_case "typed_signal" `Quick test_typed_signal;
      Alcotest.test_case "guard_choice" `Quick test_guard_choice;
    ] )

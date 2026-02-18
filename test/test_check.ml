(** Tests for {!Fpp.Check}. *)

let parse s =
  match Fpp.parse_string s with
  | tu -> tu
  | exception Fpp.Parse_error e ->
      Alcotest.failf "parse error: %a" Fpp.pp_error e

let diags s = Fpp.Check.run Fpp.Check.default (parse s)

let errors s =
  diags s |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)

let msg_contains ~substr msg =
  let len = String.length substr in
  let mlen = String.length msg in
  if len > mlen then false
  else
    let found = ref false in
    for i = 0 to mlen - len do
      if String.sub msg i len = substr then found := true
    done;
    !found

let expect_error ~substr s =
  let errs = errors s in
  if
    not
      (List.exists
         (fun (d : Fpp.Check.diagnostic) -> msg_contains ~substr d.msg)
         errs)
  then
    Alcotest.failf "expected error containing %S, got: [%s]" substr
      (String.concat "; "
         (List.map (fun (d : Fpp.Check.diagnostic) -> d.msg) errs))

let expect_no_errors s =
  let errs = errors s in
  if errs <> [] then
    Alcotest.failf "expected no errors, got: [%s]"
      (String.concat "; "
         (List.map (fun (d : Fpp.Check.diagnostic) -> d.msg) errs))

(* ---- Unit tests (ofpp-specific, not from upstream) ---- *)

(* --- 1. Name redefinition --- *)

let test_dup_action () =
  expect_error ~substr:"duplicate action"
    {|
    state machine M { action a  action a }
  |}

let test_dup_guard () =
  expect_error ~substr:"duplicate guard"
    {|
    state machine M { guard g  guard g }
  |}

let test_dup_signal () =
  expect_error ~substr:"duplicate signal"
    {|
    state machine M { signal s  signal s }
  |}

let test_dup_state () =
  expect_error ~substr:"duplicate state"
    {|
    state machine M { state S  state S }
  |}

let test_dup_choice () =
  expect_error ~substr:"duplicate choice"
    {|
    state machine M {
      guard g
      state S
      choice C { if g enter S else enter S }
      choice C { if g enter S else enter S }
    }
  |}

let test_dup_constant () =
  expect_error ~substr:"duplicate constant"
    {|
    state machine SM { constant c = 0  constant c = 1 }
  |}

let test_no_dup_ok () =
  expect_no_errors
    {|
    state machine M {
      action a
      guard g
      signal s
      state S
      initial enter S
    }
  |}

(* --- 2. Initial transitions --- *)

let test_sm_no_initial () =
  expect_error ~substr:"no initial transition"
    {|
    state machine M { state S }
  |}

let test_sm_multiple_initial () =
  expect_error ~substr:"multiple initial transitions"
    {|
    state machine M {
      initial enter S
      initial enter T
      state S
      state T
    }
  |}

let test_sm_empty_ok () =
  expect_error ~substr:"no initial transition" {| state machine M { } |}

let test_state_no_initial () =
  expect_error ~substr:"has substates but no initial transition"
    {|
    state machine M {
      initial enter S
      state S { state T }
    }
  |}

let test_state_multiple_initial () =
  expect_error ~substr:"multiple initial transitions"
    {|
    state machine M {
      initial enter S
      state S {
        initial enter T
        initial enter U
        state T
        state U
      }
    }
  |}

let test_state_initial_ok () =
  expect_no_errors
    {|
    state machine M {
      initial enter S
      state S {
        initial enter T
        state T
      }
    }
  |}

(* --- 3. Undefined references --- *)

let test_undef_action () =
  expect_error ~substr:"undefined action 'a'"
    {|
    state machine M {
      state S
      initial do { a } enter S
    }
  |}

let test_undef_guard () =
  expect_error ~substr:"undefined guard 'g'"
    {|
    state machine M {
      state S
      initial enter C
      choice C { if g enter S else enter S }
    }
  |}

let test_undef_signal () =
  expect_error ~substr:"undefined signal 's'"
    {|
    state machine M {
      initial enter S
      state S { on s enter S }
    }
  |}

let test_undef_state () =
  expect_error ~substr:"undefined state or choice 'S'"
    {|
    state machine M { initial enter S }
  |}

let test_undef_choice () =
  expect_error ~substr:"undefined state or choice 'C'"
    {|
    state machine M {
      state S
      initial enter C
    }
  |}

let test_nested_undef_action () =
  expect_error ~substr:"undefined action 'a'"
    {|
    state machine M {
      initial enter S
      state S {
        initial do { a } enter T
        state T
      }
    }
  |}

let test_nested_undef_guard () =
  expect_error ~substr:"undefined guard 'g'"
    {|
    state machine M {
      initial enter S
      state S {
        initial enter C
        choice C { if g enter S else enter S }
      }
    }
  |}

let test_refs_ok () =
  expect_no_errors
    {|
    state machine M {
      action a
      guard g
      signal s
      state S { on s enter S }
      initial enter S
    }
  |}

(* --- 4. Duplicate signal transitions --- *)

let test_dup_signal_trans () =
  expect_error ~substr:"duplicate transition on signal"
    {|
    state machine M {
      signal s
      initial enter S
      state S {
        on s enter S
        on s enter S
      }
    }
  |}

let test_dup_signal_nested () =
  expect_error ~substr:"duplicate transition on signal"
    {|
    state machine M {
      signal s
      initial enter S
      state S {
        initial enter T
        state T {
          on s enter T
          on s enter T
        }
      }
    }
  |}

(* --- 5. Reachability --- *)

let test_unreachable_state () =
  expect_error ~substr:"unreachable state 'T'"
    {|
    state machine M {
      signal s
      initial enter S
      state S
      state T
    }
  |}

let test_unreachable_choice () =
  expect_error ~substr:"unreachable choice 'C'"
    {|
    state machine M {
      guard g
      signal s
      initial enter S
      state S
      choice C { if g enter S else enter S }
    }
  |}

let test_reachable_ok () =
  expect_no_errors
    {|
    state machine M {
      guard g
      signal s
      initial enter S
      state S {
        on s enter C
        choice C { if g enter S1 else enter S2 }
      }
      state S1 { on s enter S }
      state S2
    }
  |}

(* --- 6. Choice cycles --- *)

let test_choice_cycle () =
  expect_error ~substr:"part of a cycle"
    {|
    state machine M {
      guard g
      initial enter C1
      choice C1 { if g enter S else enter C2 }
      choice C2 { if g enter S else enter C1 }
      state S
    }
  |}

let test_cycle_ok () =
  (* State cycles are fine, only choice-to-choice cycles are errors *)
  expect_no_errors
    {|
    state machine M {
      guard g
      signal s
      initial enter S
      state S {
        on s enter C
        choice C { if g enter S1 else enter S2 }
      }
      state S1 { on s enter S }
      state S2
    }
  |}

(* --- External SM --- *)

let test_external_sm () = expect_no_errors {| state machine M |}

(* --- 7. Signal coverage --- *)

let warnings s =
  diags s
  |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Warning)

let expect_warning ~substr s =
  let ws = warnings s in
  if
    not
      (List.exists
         (fun (d : Fpp.Check.diagnostic) -> msg_contains ~substr d.msg)
         ws)
  then
    Alcotest.failf "expected warning containing %S, got: [%s]" substr
      (String.concat "; "
         (List.map (fun (d : Fpp.Check.diagnostic) -> d.msg) ws))

let expect_no_warnings s =
  let ws = warnings s in
  if ws <> [] then
    Alcotest.failf "expected no warnings, got: [%s]"
      (String.concat "; "
         (List.map (fun (d : Fpp.Check.diagnostic) -> d.msg) ws))

let test_signal_coverage_gap () =
  expect_warning ~substr:"signal 's2' not handled in state 'S'"
    {|
    state machine M {
      signal s1
      signal s2
      initial enter S
      state S { on s1 enter S }
    }
  |}

let test_signal_coverage_inherited () =
  expect_no_warnings
    {|
    state machine M {
      signal s1
      initial enter S
      state S {
        on s1 enter S
        initial enter T
        state T
      }
    }
  |}

let test_signal_coverage_full () =
  expect_no_warnings
    {|
    state machine M {
      signal s1
      signal s2
      initial enter S
      state S {
        on s1 enter S
        on s2 enter S
      }
    }
  |}

let test_signal_coverage_no_signals () =
  expect_no_warnings
    {|
    state machine M {
      initial enter S
      state S
    }
  |}

(* --- 8. Liveness analysis --- *)

let test_liveness_cycle_no_exit () =
  expect_warning ~substr:"form a cycle with no exit"
    {|
    state machine M {
      signal s
      initial enter A
      state A { on s enter B }
      state B { on s enter A }
    }
  |}

let expect_no_liveness_warnings s =
  let ws = warnings s in
  let liveness_ws =
    List.filter
      (fun (d : Fpp.Check.diagnostic) -> msg_contains ~substr:"cycle" d.msg)
      ws
  in
  if liveness_ws <> [] then
    Alcotest.failf "expected no liveness warnings, got: [%s]"
      (String.concat "; "
         (List.map (fun (d : Fpp.Check.diagnostic) -> d.msg) liveness_ws))

let test_liveness_cycle_with_exit () =
  expect_no_liveness_warnings
    {|
    state machine M {
      signal s1
      signal s2
      initial enter A
      state A { on s1 enter B on s2 enter C }
      state B { on s1 enter A on s2 enter C }
      state C
    }
  |}

let test_liveness_three_state_cycle () =
  expect_warning ~substr:"'A', 'B', 'C'"
    {|
    state machine M {
      signal s
      initial enter A
      state A { on s enter B }
      state B { on s enter C }
      state C { on s enter A }
    }
  |}

let test_liveness_single_state () =
  expect_no_warnings
    {|
    state machine M {
      initial enter S
      state S
    }
  |}

let unit_tests =
  [
    Alcotest.test_case "dup_action" `Quick test_dup_action;
    Alcotest.test_case "dup_guard" `Quick test_dup_guard;
    Alcotest.test_case "dup_signal" `Quick test_dup_signal;
    Alcotest.test_case "dup_state" `Quick test_dup_state;
    Alcotest.test_case "dup_choice" `Quick test_dup_choice;
    Alcotest.test_case "dup_constant" `Quick test_dup_constant;
    Alcotest.test_case "no_dup_ok" `Quick test_no_dup_ok;
    Alcotest.test_case "sm_no_initial" `Quick test_sm_no_initial;
    Alcotest.test_case "sm_multiple_initial" `Quick test_sm_multiple_initial;
    Alcotest.test_case "sm_empty_ok" `Quick test_sm_empty_ok;
    Alcotest.test_case "state_no_initial" `Quick test_state_no_initial;
    Alcotest.test_case "state_multiple_initial" `Quick
      test_state_multiple_initial;
    Alcotest.test_case "state_initial_ok" `Quick test_state_initial_ok;
    Alcotest.test_case "undef_action" `Quick test_undef_action;
    Alcotest.test_case "undef_guard" `Quick test_undef_guard;
    Alcotest.test_case "undef_signal" `Quick test_undef_signal;
    Alcotest.test_case "undef_state" `Quick test_undef_state;
    Alcotest.test_case "undef_choice" `Quick test_undef_choice;
    Alcotest.test_case "nested_undef_action" `Quick test_nested_undef_action;
    Alcotest.test_case "nested_undef_guard" `Quick test_nested_undef_guard;
    Alcotest.test_case "refs_ok" `Quick test_refs_ok;
    Alcotest.test_case "dup_signal_trans" `Quick test_dup_signal_trans;
    Alcotest.test_case "dup_signal_nested" `Quick test_dup_signal_nested;
    Alcotest.test_case "unreachable_state" `Quick test_unreachable_state;
    Alcotest.test_case "unreachable_choice" `Quick test_unreachable_choice;
    Alcotest.test_case "reachable_ok" `Quick test_reachable_ok;
    Alcotest.test_case "choice_cycle" `Quick test_choice_cycle;
    Alcotest.test_case "cycle_ok" `Quick test_cycle_ok;
    Alcotest.test_case "external_sm" `Quick test_external_sm;
    Alcotest.test_case "signal_coverage_gap" `Quick test_signal_coverage_gap;
    Alcotest.test_case "signal_coverage_inherited" `Quick
      test_signal_coverage_inherited;
    Alcotest.test_case "signal_coverage_full" `Quick test_signal_coverage_full;
    Alcotest.test_case "signal_coverage_no_signals" `Quick
      test_signal_coverage_no_signals;
    Alcotest.test_case "liveness_cycle_no_exit" `Quick
      test_liveness_cycle_no_exit;
    Alcotest.test_case "liveness_cycle_with_exit" `Quick
      test_liveness_cycle_with_exit;
    Alcotest.test_case "liveness_three_state_cycle" `Quick
      test_liveness_three_state_cycle;
    Alcotest.test_case "liveness_single_state" `Quick test_liveness_single_state;
  ]

(* --- Upstream state machine check tests --- *)

let sm_dir =
  let dir = Filename.dirname Sys.executable_name in
  let candidates =
    [ Filename.concat dir "upstream"; "test/upstream"; "upstream" ]
  in
  let upstream =
    List.find_opt (fun d -> Sys.file_exists d && Sys.is_directory d) candidates
    |> Option.value ~default:"upstream"
  in
  Filename.concat upstream "state_machine"

let parse_file path =
  match Fpp.parse_file path with
  | tu -> tu
  | exception Fpp.Parse_error e ->
      Alcotest.failf "parse error: %a" Fpp.pp_error e
  | exception Fpp.Lexer_error (msg, pos) ->
      Alcotest.failf "%s:%d:%d: %s" pos.Lexing.pos_fname pos.Lexing.pos_lnum
        (pos.Lexing.pos_cnum - pos.Lexing.pos_bol)
        msg

let errors_of_file path =
  let tu = parse_file path in
  Fpp.Check.run Fpp.Check.default tu
  |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)

(* Files that upstream says should produce no errors. *)
let expected_pass =
  [
    "abs_type_ok.fpp";
    "action_ok.fpp";
    "array_ok.fpp";
    "choice_f32_f64.fpp";
    "choice_i16_i32.fpp";
    "choice_ok.fpp";
    "choice_u32_none.fpp";
    "cycle_ok.fpp";
    "enum_ok.fpp";
    "external_state_machine.fpp";
    "guard_ok.fpp";
    "nested_action_ok.fpp";
    "nested_choice_ok.fpp";
    "nested_guard_ok.fpp";
    "nested_state_ok.fpp";
    "ok.fpp";
    "signal_ok.fpp";
    "sm_choice_ok.fpp";
    "state_ok.fpp";
    "state_shadow_ok.fpp";
    "struct_ok.fpp";
  ]

(* Files that upstream says should produce errors. *)
let expected_fail =
  [
    "action.fpp";
    "action_error.fpp";
    "action_undef_type.fpp";
    "array_alias_format_not_numeric.fpp";
    "array_default_error.fpp";
    "array_format_not_numeric.fpp";
    "array_undef_constant.fpp";
    "array_undef_type.fpp";
    "choice.fpp";
    "choice_cycle.fpp";
    "choice_error.fpp";
    "choice_i32_f32.fpp";
    "choice_u32_bool.fpp";
    "choice_u32_bool_transitive.fpp";
    "constant.fpp";
    "constant_error.fpp";
    "duplicate.fpp";
    "duplicate_nested.fpp";
    "enum_default_error.fpp";
    "enum_undef_constant.fpp";
    "enum_undef_type.fpp";
    "guard.fpp";
    "guard_error.fpp";
    "guard_undef_type.fpp";
    "nested_action_error.fpp";
    "nested_choice.fpp";
    "nested_choice_error.fpp";
    "nested_guard_error.fpp";
    "nested_state.fpp";
    "nested_state_error.fpp";
    "no_substates.fpp";
    "signal.fpp";
    "signal_error.fpp";
    "signal_undef_type.fpp";
    "sm_choice_bad_else_action_type.fpp";
    "sm_choice_bad_guard_type.fpp";
    "sm_choice_bad_if_action_type.fpp";
    "sm_choice_bad_parent_else.fpp";
    "sm_choice_bad_parent_if.fpp";
    "sm_initial_bad_action_type.fpp";
    "sm_mismatched_parents.fpp";
    "sm_multiple_transitions.fpp";
    "sm_no_transition.fpp";
    "state.fpp";
    "state_choice.fpp";
    "state_choice_bad_else_action_type.fpp";
    "state_choice_bad_guard_type.fpp";
    "state_choice_bad_if_action_type.fpp";
    "state_choice_bad_if_action_type_f32_f64.fpp";
    "state_choice_bad_if_action_type_i16_i32.fpp";
    "state_choice_bad_parent_else.fpp";
    "state_choice_bad_parent_if.fpp";
    "state_entry_bad_action_type.fpp";
    "state_error.fpp";
    "state_exit_bad_action_type.fpp";
    "state_external_transition_bad_action_type.fpp";
    "state_initial_bad_action_type.fpp";
    "state_mismatched_parents.fpp";
    "state_multiple_transitions.fpp";
    "state_no_transition.fpp";
    "state_self_transition_bad_action_type.fpp";
    "state_transition_bad_guard_type.fpp";
    "struct_alias_format_not_numeric.fpp";
    "struct_default_error.fpp";
    "struct_format_not_numeric.fpp";
    "struct_undef_constant.fpp";
    "struct_undef_type.fpp";
    "type.fpp";
    "unreachable_choice.fpp";
    "unreachable_state.fpp";
  ]

let test_upstream_pass abs_path () =
  let errs = errors_of_file abs_path in
  if errs <> [] then
    Alcotest.failf "expected no errors, got: [%s]"
      (String.concat "; "
         (List.map (fun (d : Fpp.Check.diagnostic) -> d.msg) errs))

let test_upstream_fail abs_path () =
  let errs = errors_of_file abs_path in
  if errs = [] then Alcotest.fail "expected check errors but got none"

let upstream_test_cases prefix names test_fn =
  List.filter_map
    (fun name ->
      let abs_path = Filename.concat sm_dir name in
      if Sys.file_exists abs_path then
        Some (Alcotest.test_case (prefix ^ name) `Quick (test_fn abs_path))
      else None)
    names

let suite =
  ( "check",
    unit_tests
    @ upstream_test_cases "pass/" expected_pass test_upstream_pass
    @ upstream_test_cases "fail/" expected_fail test_upstream_fail )

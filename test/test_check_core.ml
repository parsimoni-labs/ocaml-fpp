(** Tests for {!Check_core}: error-level checks.

    Name redefinition, initial transitions, undefined references, duplicate
    signal transitions, reachability, choice cycles, and contextual hints. *)

open Test_helpers

(* ── Name redefinition ──────────────────────────────────────────────── *)

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

(* ── Initial transitions ────────────────────────────────────────────── *)

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

(* ── Undefined references ───────────────────────────────────────────── *)

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

(* ── Duplicate signal transitions ───────────────────────────────────── *)

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

(* ── Reachability ───────────────────────────────────────────────────── *)

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

(* ── Choice cycles ──────────────────────────────────────────────────── *)

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

(* ── Contextual hints ───────────────────────────────────────────────── *)

let test_undef_action_hint_guard () =
  expect_error ~substr:"a guard 'g' exists"
    {|
    state machine M {
      guard g
      state S
      initial do { g } enter S
    }
  |}

let test_undef_guard_hint_action () =
  expect_error ~substr:"an action 'a' exists"
    {|
    state machine M {
      action a
      state S
      initial enter C
      choice C { if a enter S else enter S }
    }
  |}

let test_undef_signal_hint_state () =
  expect_error ~substr:"a state 's' exists"
    {|
    state machine M {
      initial enter S
      state S { on s enter S }
      state s
    }
  |}

(* ── Suite ──────────────────────────────────────────────────────────── *)

let suite =
  ( "check_core",
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
      Alcotest.test_case "undef_action_hint_guard" `Quick
        test_undef_action_hint_guard;
      Alcotest.test_case "undef_guard_hint_action" `Quick
        test_undef_guard_hint_action;
      Alcotest.test_case "undef_signal_hint_state" `Quick
        test_undef_signal_hint_state;
    ] )

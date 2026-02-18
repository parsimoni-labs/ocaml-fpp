(** Tests for {!Check_warn}: warning-level analyses.

    Signal coverage, liveness, unused declarations, transition shadowing, and
    deadlock detection. *)

open Check_test_helpers

(* ── Signal coverage ────────────────────────────────────────────────── *)

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

(* ── Liveness ───────────────────────────────────────────────────────── *)

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
      (format_diags liveness_ws)

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

(* ── Unused declarations ────────────────────────────────────────────── *)

let test_unused_action () =
  expect_warning ~substr:"unused action 'a'"
    {|
    state machine M {
      action a
      signal s
      initial enter S
      state S { on s enter S }
    }
  |}

let test_unused_guard () =
  expect_warning ~substr:"unused guard 'g'"
    {|
    state machine M {
      guard g
      signal s
      initial enter S
      state S { on s enter S }
    }
  |}

let test_unused_signal () =
  expect_warning ~substr:"unused signal 's2'"
    {|
    state machine M {
      signal s1
      signal s2
      initial enter S
      state S { on s1 enter S }
    }
  |}

let test_all_used () =
  expect_no_warnings
    {|
    state machine M {
      action a
      guard g
      signal s
      initial enter C
      choice C { if g do { a } enter S else enter S }
      state S { on s enter S }
    }
  |}

let test_action_used_in_entry () =
  expect_no_warnings
    {|
    state machine M {
      action a
      signal s
      initial enter S
      state S {
        entry do { a }
        on s enter S
      }
    }
  |}

(* ── Transition shadowing ───────────────────────────────────────────── *)

let test_shadow_child_overrides_parent () =
  expect_warning ~substr:"shadows parent handler for signal 's'"
    {|
    state machine M {
      signal s
      initial enter P
      state P {
        on s enter P
        initial enter C
        state C { on s enter C }
      }
    }
  |}

let test_shadow_no_overlap () =
  expect_no_warnings
    {|
    state machine M {
      signal s1
      signal s2
      initial enter P
      state P {
        on s1 enter P
        initial enter C
        state C { on s2 enter C }
      }
    }
  |}

let test_shadow_grandchild () =
  expect_warning ~substr:"shadows parent handler for signal 's'"
    {|
    state machine M {
      signal s
      initial enter P
      state P {
        on s enter P
        initial enter M1
        state M1 {
          initial enter G
          state G { on s enter G }
        }
      }
    }
  |}

(* ── Deadlock detection ─────────────────────────────────────────────── *)

let test_deadlock_sink_state () =
  expect_warning ~substr:"no outgoing transitions (potential deadlock)"
    {|
    state machine M {
      signal s
      initial enter A
      state A { on s enter B }
      state B
    }
  |}

let test_deadlock_inherited_handler () =
  expect_no_warnings
    {|
    state machine M {
      signal s
      initial enter P
      state P {
        on s enter P
        initial enter C
        state C
      }
    }
  |}

let test_deadlock_no_signals () =
  expect_no_warnings
    {|
    state machine M {
      initial enter S
      state S
    }
  |}

(* ── Guard completeness ────────────────────────────────────────────── *)

let test_guard_completeness_no_else () =
  expect_warning ~substr:"no else branch"
    {|
    state machine M {
      guard g
      initial enter C
      state S
      choice C { if g enter S }
    }
  |}

let test_guard_completeness_with_else () =
  expect_no_warnings
    {|
    state machine M {
      guard g
      initial enter C
      state S
      choice C { if g enter S else enter S }
    }
  |}

let test_guard_completeness_nested_no_else () =
  expect_warning ~substr:"no else branch"
    {|
    state machine M {
      guard g
      signal s
      initial enter S
      state S {
        on s enter C
        initial enter T
        state T
        choice C { if g enter T }
      }
    }
  |}

let test_guard_completeness_nested_with_else () =
  expect_no_warnings
    {|
    state machine M {
      guard g
      signal s
      initial enter S
      state S {
        on s enter C
        initial enter T
        state T
        choice C { if g enter T else enter T }
      }
    }
  |}

(* ── Suite ──────────────────────────────────────────────────────────── *)

let suite =
  ( "check_warn",
    [
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
      Alcotest.test_case "liveness_single_state" `Quick
        test_liveness_single_state;
      Alcotest.test_case "unused_action" `Quick test_unused_action;
      Alcotest.test_case "unused_guard" `Quick test_unused_guard;
      Alcotest.test_case "unused_signal" `Quick test_unused_signal;
      Alcotest.test_case "all_used" `Quick test_all_used;
      Alcotest.test_case "action_used_in_entry" `Quick test_action_used_in_entry;
      Alcotest.test_case "shadow_child_overrides_parent" `Quick
        test_shadow_child_overrides_parent;
      Alcotest.test_case "shadow_no_overlap" `Quick test_shadow_no_overlap;
      Alcotest.test_case "shadow_grandchild" `Quick test_shadow_grandchild;
      Alcotest.test_case "deadlock_sink_state" `Quick test_deadlock_sink_state;
      Alcotest.test_case "deadlock_inherited_handler" `Quick
        test_deadlock_inherited_handler;
      Alcotest.test_case "deadlock_no_signals" `Quick test_deadlock_no_signals;
      Alcotest.test_case "guard_completeness_no_else" `Quick
        test_guard_completeness_no_else;
      Alcotest.test_case "guard_completeness_with_else" `Quick
        test_guard_completeness_with_else;
      Alcotest.test_case "guard_completeness_nested_no_else" `Quick
        test_guard_completeness_nested_no_else;
      Alcotest.test_case "guard_completeness_nested_with_else" `Quick
        test_guard_completeness_nested_with_else;
    ] )

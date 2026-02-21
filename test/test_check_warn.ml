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

let test_guard_nested_no_else () =
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

let test_guard_nested_with_else () =
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

(* ── Unconnected ports: rate group scheduling ─────────────────────── *)

let test_unconnected_unscheduled_active () =
  expect_warning
    ~substr:"input port 'sensor.schedIn' has no incoming connection"
    {|
    port Sched
    active component Sensor {
      sync input port schedIn: Sched
      async input port cmdIn: Sched
    }
    passive component RateGroupDriver {
      output port rateGroupOut: [2] Sched
    }
    instance sensor: Sensor base id 0x100 \
      queue size 10 \
      stack size 1024 \
      priority 10
    instance rgDriver: RateGroupDriver base id 0x200
    topology T {
      instance sensor
      instance rgDriver
    }
  |}

let test_unconnected_scheduled_active () =
  expect_no_warnings
    {|
    port Sched
    active component Sensor {
      sync input port schedIn: Sched
      async input port cmdIn: Sched
    }
    passive component RateGroupDriver {
      output port rateGroupOut: [2] Sched
    }
    instance sensor: Sensor base id 0x100 \
      queue size 10 \
      stack size 1024 \
      priority 10
    instance rgDriver: RateGroupDriver base id 0x200
    topology T {
      instance sensor
      instance rgDriver
      connections RateGroups {
        rgDriver.rateGroupOut -> sensor.schedIn
        rgDriver.rateGroupOut -> sensor.cmdIn
      }
    }
  |}

(* ── Warning spec ──────────────────────────────────────────────────── *)

let test_parse_spec_all () =
  match Fpp.Check.parse_spec "all" with
  | Ok [ Fpp.Check.Enable_all ] -> ()
  | _ -> Alcotest.fail "expected Enable_all"

let test_parse_spec_A () =
  match Fpp.Check.parse_spec "A" with
  | Ok [ Fpp.Check.Enable_all ] -> ()
  | _ -> Alcotest.fail "expected Enable_all from 'A'"

let test_parse_spec_disable_all () =
  match Fpp.Check.parse_spec "-all" with
  | Ok [ Fpp.Check.Disable_all ] -> ()
  | _ -> Alcotest.fail "expected Disable_all"

let test_parse_spec_abbreviations () =
  match Fpp.Check.parse_spec "-cov,+liv" with
  | Ok [ Fpp.Check.Disable Coverage; Fpp.Check.Enable Liveness ] -> ()
  | _ -> Alcotest.fail "expected Disable Coverage, Enable Liveness"

let test_parse_spec_bare_names () =
  match Fpp.Check.parse_spec "deadlock,unused" with
  | Ok [ Fpp.Check.Enable Deadlock; Fpp.Check.Enable Unused ] -> ()
  | _ -> Alcotest.fail "expected Enable Deadlock, Enable Unused"

let test_parse_spec_unknown () =
  match Fpp.Check.parse_spec "bogus" with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected error for unknown analysis"

let parse_spec_or_fail s =
  match Fpp.Check.parse_spec s with
  | Ok ds -> ds
  | Error msg -> Alcotest.failf "parse_spec failed: %s" msg

let warnings_with ~warning_spec ~error_spec s =
  let ws = parse_spec_or_fail warning_spec in
  let es = parse_spec_or_fail error_spec in
  diags_with_config ~warning_spec:ws ~error_spec:es s
  |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Warning)

let test_config_disable_coverage () =
  let ws =
    warnings_with ~warning_spec:"-cov" ~error_spec:""
      {|
    state machine M {
      signal s1
      signal s2
      initial enter S
      state S { on s1 enter S }
    }
  |}
  in
  let has_coverage =
    List.exists
      (fun (d : Fpp.Check.diagnostic) ->
        msg_contains ~substr:"not handled" d.msg)
      ws
  in
  if has_coverage then Alcotest.fail "coverage should be disabled"

let test_error_promotion () =
  let ds =
    let ws = parse_spec_or_fail "" in
    let es = parse_spec_or_fail "all" in
    diags_with_config ~warning_spec:ws ~error_spec:es
      {|
      state machine M {
        signal s1
        signal s2
        initial enter S
        state S { on s1 enter S }
      }
    |}
  in
  let promoted =
    List.filter
      (fun (d : Fpp.Check.diagnostic) ->
        d.severity = `Error && msg_contains ~substr:"not handled" d.msg)
      ds
  in
  if promoted = [] then Alcotest.fail "expected promoted errors for coverage"

let test_disabled_not_promoted () =
  let config =
    Fpp.Check.config
      ~warning_spec:
        (match Fpp.Check.parse_spec "-cov" with Ok ds -> ds | _ -> [])
      ~error_spec:
        (match Fpp.Check.parse_spec "all" with Ok ds -> ds | _ -> [])
  in
  let level = Fpp.Check.level_of config Fpp.Check.Coverage in
  if level <> Fpp.Check.Off then
    Alcotest.fail "disabled analysis should stay Off even with -e all"

let test_config_only_deadlock () =
  let config =
    Fpp.Check.config
      ~warning_spec:
        (match Fpp.Check.parse_spec "-all,+deadlock" with
        | Ok ds -> ds
        | _ -> [])
      ~error_spec:[]
  in
  List.iter
    (fun a ->
      let expected =
        if a = Fpp.Check.Deadlock then Fpp.Check.Warning else Fpp.Check.Off
      in
      let actual = Fpp.Check.level_of config a in
      if actual <> expected then
        Alcotest.failf "expected %s for %s"
          (match expected with
          | Off -> "Off"
          | Warning -> "Warning"
          | Error -> "Error")
          (Fpp.Check.string_of_analysis a))
    Fpp.Check.all_analyses

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
      Alcotest.test_case "guard_nested_no_else" `Quick test_guard_nested_no_else;
      Alcotest.test_case "guard_nested_with_else" `Quick
        test_guard_nested_with_else;
      Alcotest.test_case "unconnected_unscheduled_active" `Quick
        test_unconnected_unscheduled_active;
      Alcotest.test_case "unconnected_scheduled_active" `Quick
        test_unconnected_scheduled_active;
      Alcotest.test_case "parse_spec_all" `Quick test_parse_spec_all;
      Alcotest.test_case "parse_spec_A" `Quick test_parse_spec_A;
      Alcotest.test_case "parse_spec_disable_all" `Quick
        test_parse_spec_disable_all;
      Alcotest.test_case "parse_spec_abbreviations" `Quick
        test_parse_spec_abbreviations;
      Alcotest.test_case "parse_spec_bare_names" `Quick
        test_parse_spec_bare_names;
      Alcotest.test_case "parse_spec_unknown" `Quick test_parse_spec_unknown;
      Alcotest.test_case "config_disable_coverage" `Quick
        test_config_disable_coverage;
      Alcotest.test_case "error_promotion" `Quick test_error_promotion;
      Alcotest.test_case "disabled_not_promoted" `Quick
        test_disabled_not_promoted;
      Alcotest.test_case "config_only_deadlock" `Quick test_config_only_deadlock;
    ] )

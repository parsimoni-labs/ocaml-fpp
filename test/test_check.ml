(** Upstream state machine check tests.

    Runs the checker against the upstream test corpus: files in [ok/] must
    produce no errors, files in [fail/] must produce at least one error. *)

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
      (Check_test_helpers.format_diags errs)

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
    upstream_test_cases "pass/" expected_pass test_upstream_pass
    @ upstream_test_cases "fail/" expected_fail test_upstream_fail )

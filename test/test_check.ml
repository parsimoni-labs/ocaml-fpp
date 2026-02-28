(** Upstream semantic check tests.

    Runs the checker against ALL upstream fpp-check test files. Files with "ok"
    in the name must produce no errors; all others must produce at least one
    error whose message matches the expected pattern for that folder/file. Test
    failures indicate missing check implementations. *)

(* ── Upstream directory discovery ──────────────────────────────────── *)

let upstream_dir =
  let dir = Filename.dirname Sys.executable_name in
  let candidates =
    [ Filename.concat dir "upstream"; "test/upstream"; "upstream" ]
  in
  List.find_opt (fun d -> Sys.file_exists d && Sys.is_directory d) candidates
  |> Option.value ~default:"upstream"

(** Directories from fpp-check test suite. Excludes codegen/ (code generation
    tests) and syntax/ (parser tests), which are handled by {!Test_fpp}. *)
let check_dirs =
  [
    "array";
    "command";
    "component";
    "component_instance_def";
    "component_instance_spec";
    "connection_direct";
    "connection_pattern";
    "constant";
    "container";
    "cycle";
    "enum";
    "event";
    "expr";
    "interface";
    "internal_port";
    "invalid_symbols";
    "param";
    "port";
    "port_instance";
    "port_matching";
    "port_numbering";
    "record";
    "redef";
    "spec_init";
    "spec_loc";
    "state_machine";
    "state_machine_instance";
    "struct";
    "tlm_channel";
    "tlm_packets";
    "top_import";
    "type";
    "unconnected";
  ]

(* ── File classification ───────────────────────────────────────────── *)

(** Files that should pass but do not follow the _ok naming convention. *)
let extra_pass =
  [
    "enum/explicit.fpp";
    "enum/implied.fpp";
    "state_machine/choice_f32_f64.fpp";
    "state_machine/choice_i16_i32.fpp";
    "state_machine/choice_u32_none.fpp";
    "state_machine/external_state_machine.fpp";
    "tlm_packets/instances.fpp";
    "array/large_size.fpp";
    "top_import/basic.fpp";
    "port_instance/async_input_active.fpp";
    "top_import/instance_private_public.fpp";
    "array/format_numeric.fpp";
    "struct/format_numeric.fpp";
    "struct/format_alias_numeric.fpp";
    "component_instance_def/active_no_priority.fpp";
    "component_instance_def/active_no_stack_size.fpp";
    "component_instance_def/large_int.fpp";
    "component_instance_def/two_empty_ranges.fpp";
    "port_instance/async_input_ref_params.fpp";
    "port_instance/async_product_recv_active.fpp";
    "state_machine_instance/inside_active.fpp";
    "state_machine_instance/outside_active.fpp";
    "top_import/instance_public.fpp";
    "unconnected/basic.fpp";
    "unconnected/internal.fpp";
  ]

let is_ok_file ~dir name =
  let rel = dir ^ "/" ^ name in
  name = "ok.fpp"
  || Filename.check_suffix name "_ok.fpp"
  || List.mem rel extra_pass

(* ── Expected error patterns ───────────────────────────────────────── *)

(** Expected error message substrings per test file. When defined, at least one
    produced error must contain one of the listed substrings. This prevents
    false passes where an unrelated check (e.g. instance-not-in-topology) masks
    a missing check. Files not listed here use the default behaviour: any error
    suffices. *)
let expected_error_patterns =
  [
    (* connection_direct: each file tests a specific connection property *)
    ("connection_direct/invalid_directions.fpp", [ "direction" ]);
    ("connection_direct/internal_port.fpp", [ "internal" ]);
    ( "connection_direct/invalid_port_instance.fpp",
      [ "no port"; "has no port"; "undefined port" ] );
    ( "connection_direct/invalid_port_number.fpp",
      [ "port number"; "index"; "out of range"; "exceeds port size" ] );
  ]

(* ── Check runner ──────────────────────────────────────────────────── *)

let all_errors_config =
  Fpp.Check.config ~warning_spec:[ Fpp.Check.Enable_all ]
    ~error_spec:[ Fpp.Check.Enable_all ]

let diags_of_file ?(config = Fpp.Check.default) path =
  match Fpp.parse_file path with
  | tu -> Fpp.Check.run config tu
  | exception Fpp.Parse_error _ -> []
  | exception Fpp.Lexer_error _ -> []

let errors_of_file ?config path =
  diags_of_file ?config path
  |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)

let test_pass abs_path () =
  let errs = errors_of_file abs_path in
  if errs <> [] then
    Alcotest.failf "expected no errors, got: [%s]"
      (Check_test_helpers.format_diags errs)

let test_fail ~rel abs_path () =
  let diags = diags_of_file ~config:all_errors_config abs_path in
  if diags = [] then Alcotest.fail "expected check diagnostics but got none"
  else
    match List.assoc_opt rel expected_error_patterns with
    | None -> ()
    | Some patterns ->
        let has_match =
          List.exists
            (fun (d : Fpp.Check.diagnostic) ->
              List.exists
                (fun pat -> Check_test_helpers.msg_contains ~substr:pat d.msg)
                patterns)
            diags
        in
        if not has_match then
          Alcotest.failf
            "diagnostics found but none match expected patterns [%s]: %s"
            (String.concat "; " patterns)
            (Check_test_helpers.format_diags diags)

(* ── Suite construction ────────────────────────────────────────────── *)

let discover_tests () =
  List.concat_map
    (fun dir ->
      let dir_path = Filename.concat upstream_dir dir in
      if not (Sys.file_exists dir_path && Sys.is_directory dir_path) then []
      else
        Sys.readdir dir_path |> Array.to_list |> List.sort String.compare
        |> List.filter_map (fun name ->
            if not (Filename.check_suffix name ".fpp") then None
            else
              let abs_path = Filename.concat dir_path name in
              let rel = dir ^ "/" ^ name in
              if is_ok_file ~dir name then
                Some
                  (Alcotest.test_case ("pass/" ^ rel) `Quick
                     (test_pass abs_path))
              else
                Some
                  (Alcotest.test_case ("fail/" ^ rel) `Quick
                     (test_fail ~rel abs_path))))
    check_dirs

let suite = ("check", discover_tests ())

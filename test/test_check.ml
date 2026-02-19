(** Upstream semantic check tests.

    Runs the checker against ALL upstream fpp-check test files. Files with "ok"
    in the name must produce no errors; all others must produce at least one
    error. Test failures indicate missing check implementations. *)

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
  ]

let is_ok_file ~dir name =
  let rel = dir ^ "/" ^ name in
  name = "ok.fpp"
  || Filename.check_suffix name "_ok.fpp"
  || List.mem rel extra_pass

(* ── Check runner ──────────────────────────────────────────────────── *)

let errors_of_file path =
  match Fpp.parse_file path with
  | tu ->
      Fpp.Check.run Fpp.Check.default tu
      |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)
  | exception Fpp.Parse_error _ -> []
  | exception Fpp.Lexer_error _ -> []

let test_pass abs_path () =
  let errs = errors_of_file abs_path in
  if errs <> [] then
    Alcotest.failf "expected no errors, got: [%s]"
      (Check_test_helpers.format_diags errs)

let test_fail abs_path () =
  let errs = errors_of_file abs_path in
  if errs = [] then Alcotest.fail "expected check errors but got none"

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
              if is_ok_file ~dir name then
                Some
                  (Alcotest.test_case
                     ("pass/" ^ dir ^ "/" ^ name)
                     `Quick (test_pass abs_path))
              else
                Some
                  (Alcotest.test_case
                     ("fail/" ^ dir ^ "/" ^ name)
                     `Quick (test_fail abs_path))))
    check_dirs

let suite = ("check", discover_tests ())

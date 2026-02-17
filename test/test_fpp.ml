(** Tests for FPP parser. *)

let _test_file file () =
  match Fpp.parse_file file with
  | _tu -> ()
  | exception Fpp.Parse_error e -> Alcotest.failf "%a" Fpp.pp_error e

let test_string ?filename content () =
  match Fpp.parse_string ?filename content with
  | _tu -> ()
  | exception Fpp.Parse_error e -> Alcotest.failf "%a" Fpp.pp_error e

(* Basic syntax tests *)
let test_empty () = test_string "" ()
let test_constant () = test_string {|constant x = 42|} ()
let test_module () = test_string {|module M { constant x = 1 }|} ()
let test_enum () = test_string {|enum E { A, B, C }|} ()
let test_struct () = test_string {|struct S { x: U32 }|} ()
let test_array () = test_string {|array A = [3] U32|} ()
let test_port () = test_string {|port P(x: U32)|} ()
let test_passive_component () = test_string {|passive component C { }|} ()
let test_active_component () = test_string {|active component C { }|} ()
let test_queued_component () = test_string {|queued component C { }|} ()

let test_component_with_ports () =
  test_string
    {|
    passive component C {
      sync input port cmdIn: Fw.Cmd
      output port cmdRespOut: Fw.CmdResponse
    }
  |}
    ()

let test_component_with_commands () =
  test_string
    {|
    passive component C {
      sync command DO_THING(x: U32) opcode 0x10
      async command DO_ASYNC(y: string) priority 10
    }
  |}
    ()

let test_component_with_telemetry () =
  test_string
    {|
    passive component C {
      telemetry counter: U32 id 0 update on change
    }
  |}
    ()

let test_component_with_events () =
  test_string
    {|
    passive component C {
      event MyEvent(x: U32) severity activity high format "x={}"
    }
  |}
    ()

let test_component_with_params () =
  test_string
    {|
    passive component C {
      param threshold: U32 default 100 id 0
    }
  |}
    ()

let test_instance () =
  test_string
    {|
    module M { passive component C { } }
    instance c: M.C base id 0x100
  |}
    ()

let test_topology () =
  test_string
    {|
    passive component C { }
    instance c: C base id 0
    topology T { instance c }
  |}
    ()

let test_connections () =
  test_string
    {|
    passive component A { output port out: P }
    passive component B { sync input port in: P }
    instance a: A base id 0
    instance b: B base id 10
    topology T {
      instance a
      instance b
      connections Direct { a.out -> b.in }
    }
  |}
    ()

let test_annotations () =
  test_string
    {|
    @ This is a pre-annotation
    constant x = 1
    constant y = 2 @< This is a post-annotation
  |}
    ()

let test_multiline_string () =
  test_string
    {|
    constant s = """
      This is a
      multiline string
    """
  |}
    ()

(* Upstream FPP test files *)
let upstream_dir =
  let dir = Filename.dirname Sys.executable_name in
  let candidates =
    [ Filename.concat dir "upstream"; "test/upstream"; "upstream" ]
  in
  List.find_opt (fun d -> Sys.file_exists d && Sys.is_directory d) candidates
  |> Option.value ~default:"upstream"

(* Files expected to fail: syntax error tests and known limitations *)
let expected_failures =
  [
    "syntax/illegal-character.fpp";
    (* intentional lexer error *)
    "syntax/parse-error.fpp";
    (* intentional parse error *)
  ]

let is_expected_failure path =
  List.exists
    (fun suffix ->
      String.length path >= String.length suffix
      && String.sub path
           (String.length path - String.length suffix)
           (String.length suffix)
         = suffix)
    expected_failures

(* Recursively find all .fpp files under a directory *)
let rec find_fpp_files dir prefix =
  if not (Sys.file_exists dir && Sys.is_directory dir) then []
  else
    Sys.readdir dir |> Array.to_list |> List.sort String.compare
    |> List.concat_map (fun name ->
        let path = Filename.concat dir name in
        let rel = if prefix = "" then name else Filename.concat prefix name in
        if Sys.is_directory path then find_fpp_files path rel
        else if Filename.check_suffix name ".fpp" then [ (rel, path) ]
        else [])

let test_upstream_file (rel_path, abs_path) () =
  if is_expected_failure rel_path then
    match Fpp.parse_file abs_path with
    | _tu ->
        Alcotest.failf "expected failure but %s parsed successfully" rel_path
    | exception Fpp.Parse_error _ -> ()
    | exception Fpp.Lexer_error _ -> ()
  else
    match Fpp.parse_file abs_path with
    | _tu -> ()
    | exception Fpp.Parse_error e -> Alcotest.failf "%a" Fpp.pp_error e
    | exception Fpp.Lexer_error (msg, pos) ->
        Alcotest.failf "%s:%d:%d: %s" pos.Lexing.pos_fname pos.Lexing.pos_lnum
          (pos.Lexing.pos_cnum - pos.Lexing.pos_bol)
          msg

let suite =
  [
    ( "basic",
      [
        Alcotest.test_case "empty" `Quick test_empty;
        Alcotest.test_case "constant" `Quick test_constant;
        Alcotest.test_case "module" `Quick test_module;
        Alcotest.test_case "enum" `Quick test_enum;
        Alcotest.test_case "struct" `Quick test_struct;
        Alcotest.test_case "array" `Quick test_array;
        Alcotest.test_case "port" `Quick test_port;
        Alcotest.test_case "annotations" `Quick test_annotations;
        Alcotest.test_case "multiline_string" `Quick test_multiline_string;
      ] );
    ( "components",
      [
        Alcotest.test_case "passive" `Quick test_passive_component;
        Alcotest.test_case "active" `Quick test_active_component;
        Alcotest.test_case "queued" `Quick test_queued_component;
        Alcotest.test_case "with_ports" `Quick test_component_with_ports;
        Alcotest.test_case "with_commands" `Quick test_component_with_commands;
        Alcotest.test_case "with_telemetry" `Quick test_component_with_telemetry;
        Alcotest.test_case "with_events" `Quick test_component_with_events;
        Alcotest.test_case "with_params" `Quick test_component_with_params;
      ] );
    ( "topology",
      [
        Alcotest.test_case "instance" `Quick test_instance;
        Alcotest.test_case "topology" `Quick test_topology;
        Alcotest.test_case "connections" `Quick test_connections;
      ] );
    ( "upstream",
      List.map
        (fun ((rel, _) as entry) ->
          Alcotest.test_case rel `Quick (test_upstream_file entry))
        (find_fpp_files upstream_dir "") );
  ]

(** Tests for {!Check_tu}: translation unit orchestrator.

    Verifies the top-level check pipeline that coordinates redefinition, symbol,
    definition, component, and topology checks. These tests exercise
    cross-module interactions that span multiple check phases. *)

open Test_helpers

(* ── Empty and minimal TUs ───────────────────────────────────────────── *)

let test_empty_tu () = expect_no_errors ""
let test_single_constant () = expect_no_errors {| constant a = 1 |}

(* ── Module scoping ──────────────────────────────────────────────────── *)

let test_module_wrapping () =
  expect_no_errors
    {|
    module M {
      constant a = 1
      enum E { X }
      struct S { f: U32 }
      array A = [2] U32
    }
  |}

let test_nested_modules () =
  expect_no_errors
    {|
    module M {
      module N {
        constant a = 42
      }
      constant b = N.a
    }
  |}

(* ── Cross-phase interactions ────────────────────────────────────────── *)

let test_redef_and_usage () =
  expect_error ~substr:"duplicate definition"
    {|
    constant a = 1
    constant a = 2
    constant b = a
  |}

let test_type_used_in_array () =
  expect_no_errors {|
    enum E { X, Y, Z }
    array A = [3] E
  |}

let test_constant_used_in_enum () =
  expect_no_errors
    {|
    constant base = 10
    enum E { X = base, Y = base + 1 }
  |}

(* ── Full translation unit ───────────────────────────────────────────── *)

let test_component_and_instance () =
  expect_no_errors
    {|
    passive component C { }
    instance c: C base id 0x100
  |}

let test_topology_pipeline () =
  expect_no_errors
    {|
    passive component Sensor { }
    instance s: Sensor base id 0x100
    topology Deploy {
      instance s
    }
  |}

let suite =
  ( "check_tu",
    [
      Alcotest.test_case "empty_tu" `Quick test_empty_tu;
      Alcotest.test_case "single_constant" `Quick test_single_constant;
      Alcotest.test_case "module_wrapping" `Quick test_module_wrapping;
      Alcotest.test_case "nested_modules" `Quick test_nested_modules;
      Alcotest.test_case "redef_and_usage" `Quick test_redef_and_usage;
      Alcotest.test_case "type_used_in_array" `Quick test_type_used_in_array;
      Alcotest.test_case "constant_used_in_enum" `Quick
        test_constant_used_in_enum;
      Alcotest.test_case "component_and_instance" `Quick
        test_component_and_instance;
      Alcotest.test_case "topology_pipeline" `Quick test_topology_pipeline;
    ] )

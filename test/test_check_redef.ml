(** Tests for {!Check_redef}: redefinition detection.

    Validates that duplicate definitions within the same scope are flagged.
    Derived from upstream [redef/] tests (constant, enum, component, module name
    collisions, struct members, enum constants). *)

open Check_test_helpers

(* ── Pass cases ──────────────────────────────────────────────────────── *)

let test_distinct_constants () =
  expect_no_errors {| constant a = 1  constant b = 2 |}

let test_same_name_different_modules () =
  expect_no_errors
    {|
    module M1 { constant x = 0 }
    module M2 { constant x = 1 }
  |}

(* ── Fail cases: top-level redefinitions ─────────────────────────────── *)

let test_duplicate_constant () =
  expect_error ~substr:"duplicate definition"
    {|
    constant x = 0
    constant x = 1
  |}

let test_duplicate_enum () =
  expect_error ~substr:"duplicate definition"
    {|
    enum E { X }
    enum E { Y }
  |}

let test_duplicate_struct () =
  expect_error ~substr:"duplicate definition"
    {|
    struct S { x: U32 }
    struct S { y: F64 }
  |}

let test_duplicate_component () =
  expect_error ~substr:"duplicate definition"
    {|
    passive component C { }
    passive component C { }
  |}

let test_duplicate_array () =
  expect_error ~substr:"duplicate definition"
    {|
    array A = [3] U32
    array A = [4] F64
  |}

(* ── Fail cases: cross-kind collisions ──────────────────────────────── *)

let test_constant_module_collision () =
  expect_error ~substr:"duplicate definition"
    {|
    constant c = 0
    module c { }
  |}

(* ── Fail cases: member-level redefinitions ─────────────────────────── *)

let test_duplicate_struct_member () =
  expect_error ~substr:"duplicate struct member"
    {|
    struct S { x: F32, x: U16 }
  |}

let test_duplicate_enum_constant () =
  expect_error ~substr:"duplicate enum constant" {|
    enum E { X, X }
  |}

let suite =
  ( "check_redef",
    [
      Alcotest.test_case "distinct_constants" `Quick test_distinct_constants;
      Alcotest.test_case "same_name_different_modules" `Quick
        test_same_name_different_modules;
      Alcotest.test_case "duplicate_constant" `Quick test_duplicate_constant;
      Alcotest.test_case "duplicate_enum" `Quick test_duplicate_enum;
      Alcotest.test_case "duplicate_struct" `Quick test_duplicate_struct;
      Alcotest.test_case "duplicate_component" `Quick test_duplicate_component;
      Alcotest.test_case "duplicate_array" `Quick test_duplicate_array;
      Alcotest.test_case "constant_module_collision" `Quick
        test_constant_module_collision;
      Alcotest.test_case "duplicate_struct_member" `Quick
        test_duplicate_struct_member;
      Alcotest.test_case "duplicate_enum_constant" `Quick
        test_duplicate_enum_constant;
    ] )

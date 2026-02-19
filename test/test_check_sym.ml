(** Tests for {!Check_sym}: symbol dependency and cycle detection.

    Validates that circular constant/type dependencies are detected and that the
    dependency graph is built correctly. Derived from upstream [cycle/] tests.
*)

open Check_test_helpers

(* ── Pass cases ──────────────────────────────────────────────────────── *)

let test_linear_constant_chain () =
  expect_no_errors
    {|
    constant a = 1
    constant b = a
    constant c = b + 1
  |}

let test_module_qualified_constant () =
  expect_no_errors
    {|
    module M {
      constant a = 1
    }
    constant b = M.a
  |}

(* ── Fail cases ──────────────────────────────────────────────────────── *)

let test_two_constant_cycle () =
  expect_error ~substr:"cycle" {|
    constant a = b
    constant b = a
  |}

let test_three_constant_cycle () =
  expect_error ~substr:"cycle"
    {|
    constant a = b
    constant b = c
    constant c = a
  |}

let test_self_referencing_constant () =
  expect_error ~substr:"cycle" {|
    constant a = a
  |}

let suite =
  ( "check_sym",
    [
      Alcotest.test_case "linear_constant_chain" `Quick
        test_linear_constant_chain;
      Alcotest.test_case "module_qualified_constant" `Quick
        test_module_qualified_constant;
      Alcotest.test_case "two_constant_cycle" `Quick test_two_constant_cycle;
      Alcotest.test_case "three_constant_cycle" `Quick test_three_constant_cycle;
      Alcotest.test_case "self_referencing_constant" `Quick
        test_self_referencing_constant;
    ] )

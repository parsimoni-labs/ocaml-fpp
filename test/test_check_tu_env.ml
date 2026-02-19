(** Tests for {!Check_tu_env}: translation unit environment and expression
    evaluation.

    Exercises constant resolution, expression evaluation, module-qualified
    access, and component lookup through the public {!Fpp.Check} API. Derived
    from upstream [constant/] tests. *)

open Check_test_helpers

(* ── Constant resolution pass cases ──────────────────────────────────── *)

let test_constant_chain () =
  expect_no_errors
    {|
    constant a = 1
    constant b = a + 2
    constant c = b * 3
  |}

let test_negative_constant () = expect_no_errors {| constant a = -1 |}
let test_hex_constant () = expect_no_errors {| constant a = 0xFF |}

let test_module_qualified_constant () =
  expect_no_errors {|
    module M { constant a = 1 }
    constant b = M.a
  |}

let test_nested_module_constant () =
  expect_no_errors
    {|
    module M {
      module N { constant a = 42 }
    }
    constant b = M.N.a
  |}

let test_array_literal () = expect_no_errors {| constant a = [ 1, 2, 3 ] |}

let test_struct_literal () =
  expect_no_errors {| constant a = { x = 1, y = 2 } |}

(* ── Constant resolution fail cases ──────────────────────────────────── *)

let test_undefined_constant () =
  expect_error ~substr:"undefined" {| constant b = a |}

let test_undefined_in_expression () =
  expect_error ~substr:"undefined"
    {|
    constant a = 1
    constant b = a + x
  |}

(* ── Arithmetic expressions ──────────────────────────────────────────── *)

let test_binary_ops () =
  expect_no_errors
    {|
    constant a = 10
    constant b = a + 1
    constant c = a - 1
    constant d = a * 2
    constant e = a / 2
  |}

let test_parenthesised_expr () = expect_no_errors {| constant a = (1 + 2) * 3 |}

let suite =
  ( "check_tu_env",
    [
      Alcotest.test_case "constant_chain" `Quick test_constant_chain;
      Alcotest.test_case "negative_constant" `Quick test_negative_constant;
      Alcotest.test_case "hex_constant" `Quick test_hex_constant;
      Alcotest.test_case "module_qualified_constant" `Quick
        test_module_qualified_constant;
      Alcotest.test_case "nested_module_constant" `Quick
        test_nested_module_constant;
      Alcotest.test_case "array_literal" `Quick test_array_literal;
      Alcotest.test_case "struct_literal" `Quick test_struct_literal;
      Alcotest.test_case "undefined_constant" `Quick test_undefined_constant;
      Alcotest.test_case "undefined_in_expression" `Quick
        test_undefined_in_expression;
      Alcotest.test_case "binary_ops" `Quick test_binary_ops;
      Alcotest.test_case "parenthesised_expr" `Quick test_parenthesised_expr;
    ] )

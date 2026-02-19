(** Tests for {!Check_def}: type definition validation.

    Exercises array, enum, struct, constant, and type alias checks through the
    public {!Fpp.Check} API. Derived from upstream [array/], [enum/], [struct/],
    [constant/], and [type/] tests. *)

open Check_test_helpers

(* ── Array pass cases ────────────────────────────────────────────────── *)

let test_array_valid () = expect_no_errors {| array A = [3] U32 |}

let test_array_with_default () =
  expect_no_errors {| array A = [3] U32 default [ 1, 2, 3 ] |}

(* ── Array fail cases ────────────────────────────────────────────────── *)

let test_array_negative_size () =
  expect_error ~substr:"must be positive" {| array A = [-1] U32 |}

let test_array_format_on_non_numeric () =
  expect_error ~substr:"format specifier on non-numeric"
    {| array A = [3] string format "{}" |}

let test_array_default_count_mismatch () =
  expect_error ~substr:"default has" {| array A = [3] U32 default [ 1, 2 ] |}

let test_array_string_default () =
  expect_error ~substr:"must be an array expression, got string"
    {| array A = [3] U32 default "hello" |}

(* ── Enum pass cases ─────────────────────────────────────────────────── *)

let test_enum_valid () = expect_no_errors {| enum E { A, B, C } |}

let test_enum_with_default () =
  expect_no_errors {| enum Status { YES, NO, MAYBE } default MAYBE |}

let test_enum_explicit_values () =
  expect_no_errors {| enum E { X = 0, Y = 1, Z = 2 } |}

(* ── Enum fail cases ─────────────────────────────────────────────────── *)

let test_enum_string_constant () =
  expect_error ~substr:"must be numeric" {| enum E { X = "abc" } |}

let test_enum_duplicate_value () =
  expect_error ~substr:"same value"
    {|
    constant a = 2
    constant b = 1
    enum E { X = a, Y = b + 1 }
  |}

let test_enum_bad_default () =
  expect_error ~substr:"not a valid enumerator" {| enum E { A, B } default C |}

let test_enum_no_constants () =
  expect_error ~substr:"has no constants" {| enum E { } |}

(* ── Struct pass cases ───────────────────────────────────────────────── *)

let test_struct_valid () = expect_no_errors {| struct S { x: U32, y: F64 } |}

let test_struct_with_default () =
  expect_no_errors
    {|
    struct S { x: U32, y: U32 } default { x = 1, y = 2 }
  |}

(* ── Struct fail cases ───────────────────────────────────────────────── *)

let test_struct_format_on_non_numeric () =
  expect_error ~substr:"format specifier on non-numeric"
    {| struct S { x: string format "{}" } |}

let test_struct_unknown_default_member () =
  expect_error ~substr:"unknown member"
    {|
    struct S { x: U32 } default { z = 5 }
  |}

(* ── Type alias cases ────────────────────────────────────────────────── *)

let test_type_alias_valid () = expect_no_errors {| type T = U32 |}

let test_string_negative_size () =
  expect_error ~substr:"non-negative" {| array A = [3] string size -1 |}

(* ── Constant pass cases ─────────────────────────────────────────────── *)

let test_constant_arithmetic () =
  expect_no_errors
    {|
    constant a = 1
    constant b = a + 2
    constant c = b * 3
  |}

let test_constant_hex () = expect_no_errors {| constant a = 0xFF |}

(* ── Constant fail cases ─────────────────────────────────────────────── *)

let test_constant_undefined_ref () =
  expect_error ~substr:"undefined" {| constant b = a |}

let suite =
  ( "check_def",
    [
      Alcotest.test_case "array_valid" `Quick test_array_valid;
      Alcotest.test_case "array_with_default" `Quick test_array_with_default;
      Alcotest.test_case "array_negative_size" `Quick test_array_negative_size;
      Alcotest.test_case "array_format_on_non_numeric" `Quick
        test_array_format_on_non_numeric;
      Alcotest.test_case "array_default_count_mismatch" `Quick
        test_array_default_count_mismatch;
      Alcotest.test_case "array_string_default" `Quick test_array_string_default;
      Alcotest.test_case "enum_valid" `Quick test_enum_valid;
      Alcotest.test_case "enum_with_default" `Quick test_enum_with_default;
      Alcotest.test_case "enum_explicit_values" `Quick test_enum_explicit_values;
      Alcotest.test_case "enum_string_constant" `Quick test_enum_string_constant;
      Alcotest.test_case "enum_duplicate_value" `Quick test_enum_duplicate_value;
      Alcotest.test_case "enum_bad_default" `Quick test_enum_bad_default;
      Alcotest.test_case "enum_no_constants" `Quick test_enum_no_constants;
      Alcotest.test_case "struct_valid" `Quick test_struct_valid;
      Alcotest.test_case "struct_with_default" `Quick test_struct_with_default;
      Alcotest.test_case "struct_format_on_non_numeric" `Quick
        test_struct_format_on_non_numeric;
      Alcotest.test_case "struct_unknown_default_member" `Quick
        test_struct_unknown_default_member;
      Alcotest.test_case "type_alias_valid" `Quick test_type_alias_valid;
      Alcotest.test_case "string_negative_size" `Quick test_string_negative_size;
      Alcotest.test_case "constant_arithmetic" `Quick test_constant_arithmetic;
      Alcotest.test_case "constant_hex" `Quick test_constant_hex;
      Alcotest.test_case "constant_undefined_ref" `Quick
        test_constant_undefined_ref;
    ] )

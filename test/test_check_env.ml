(** Tests for {!Check_env}: name environment construction.

    The environment builder is exercised indirectly by every check test. These
    tests verify edge cases in environment construction and external state
    machine handling. *)

open Check_test_helpers

let test_external_sm () = expect_no_errors {| state machine M |}

let test_empty_body () =
  expect_error ~substr:"no initial transition" {| state machine M { } |}

let test_env_collects_all_kinds () =
  expect_no_errors
    {|
    state machine M {
      action a
      guard g
      signal s
      state S { on s enter S }
      initial enter S
    }
  |}

let suite =
  ( "check_env",
    [
      Alcotest.test_case "external_sm" `Quick test_external_sm;
      Alcotest.test_case "empty_body" `Quick test_empty_body;
      Alcotest.test_case "env_collects_all_kinds" `Quick
        test_env_collects_all_kinds;
    ] )

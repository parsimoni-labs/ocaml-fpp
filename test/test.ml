(** Tests for fpp library. *)

let () =
  Alcotest.run "fpp"
    [
      Test_fpp.suite;
      Test_ast.suite;
      Test_check_env.suite;
      Test_check_core.suite;
      Test_check_warn.suite;
      Test_check.suite;
    ]

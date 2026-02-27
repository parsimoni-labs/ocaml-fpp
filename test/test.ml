(** Tests for fpp library. *)

let () =
  Alcotest.run "fpp"
    [
      Test_fpp.suite;
      Test_ast.suite;
      Test_check_env.suite;
      Test_check_core.suite;
      Test_check_warn.suite;
      Test_check_tu_env.suite;
      Test_check_tu.suite;
      Test_check_redef.suite;
      Test_check_sym.suite;
      Test_check_def.suite;
      Test_check_comp.suite;
      Test_check_topo.suite;
      Test_check.suite;
      Test_dot.suite;
      Test_gen_ml.suite;
      Test_fpv.suite;
    ]

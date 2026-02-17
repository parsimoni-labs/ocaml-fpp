(** Tests for fpp library. *)

let () = Alcotest.run "fpp" [ Test_fpp.suite; Test_ast.suite; Test_check.suite ]

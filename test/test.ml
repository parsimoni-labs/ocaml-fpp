(** Tests for fpp library modules. *)

let () = Alcotest.run "fpp" (Test_fpp.suite @ Test_ast.suite)

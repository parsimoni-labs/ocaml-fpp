(** Tests for {!Fpp}.

    Verifies FPP parsing and AST queries including module extraction, component
    definitions, topologies, and expression evaluation. *)

val suite : (string * unit Alcotest.test_case list) list
(** [suite] is the Alcotest test suite for FPP parsing. *)

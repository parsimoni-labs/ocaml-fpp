(** Upstream semantic check conformance tests.

    Auto-discovers all upstream fpp-check test files and verifies that ofpp
    produces the same pass/fail result as the upstream compiler. *)

val suite : string * unit Alcotest.test_case list

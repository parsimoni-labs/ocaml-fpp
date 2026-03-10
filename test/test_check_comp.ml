(** Tests for {!Check_comp}: component definition validation.

    Exercises component member checks, port requirements, and import constraints
    through the public {!Fpp.Check} API. Derived from upstream [component/] and
    [component_instance_def/] tests. *)

open Test_helpers

(* ── Pass cases ──────────────────────────────────────────────────────── *)

let test_passive_component () = expect_no_errors {| passive component C { } |}

let test_passive_with_sync_port () =
  expect_no_errors
    {|
    port P
    passive component C {
      sync input port p: P
    }
  |}

let test_passive_with_members () =
  expect_no_errors
    {|
    passive component C {
      constant x = 42
      enum E { A, B }
      array A = [2] U32
      struct S { f: U32 }
    }
  |}

(* ── Async input requirement ─────────────────────────────────────────── *)

let test_active_requires_async () =
  expect_error ~substr:"must have at least one async input"
    {| active component C { } |}

let test_queued_requires_async () =
  expect_error ~substr:"must have at least one async input"
    {| queued component C { } |}

(* ── Passive restrictions ────────────────────────────────────────────── *)

let test_async_port_in_passive () =
  expect_error ~substr:"not allowed in passive"
    {|
    port P
    passive component C {
      async input port p: P
    }
  |}

let test_internal_port_in_passive () =
  expect_error ~substr:"not allowed in passive"
    {|
    passive component C {
      internal port ip
    }
  |}

let test_async_command_in_passive () =
  expect_error ~substr:"not allowed in passive"
    {|
    passive component C {
      async command c
    }
  |}

(* ── Command spec checks ────────────────────────────────────────────── *)

let test_command_negative_opcode () =
  expect_error ~substr:"non-negative"
    {|
    port P
    active component C {
      async input port p: P
      async command c opcode -1
    }
  |}

(* ── Event spec checks ──────────────────────────────────────────────── *)

let test_event_format_mismatch () =
  expect_error ~substr:"format string"
    {|
    port P
    active component C {
      async input port p: P
      event e(x: U32) severity activity high format "{} {}"
    }
  |}

(* ── Undefined type in component ─────────────────────────────────────── *)

let test_undefined_type () =
  expect_error ~substr:"undefined type"
    {|
    passive component C {
      array A = [3] Nonexistent
    }
  |}

(* ── Duplicate ID detection ──────────────────────────────────────────── *)

let test_duplicate_command_opcode () =
  expect_error ~substr:"duplicate command opcode"
    {|
    port P
    active component C {
      async input port p: P
      async command a opcode 0
      async command b opcode 0
    }
  |}

let suite =
  ( "check_comp",
    [
      Alcotest.test_case "passive_component" `Quick test_passive_component;
      Alcotest.test_case "passive_with_sync_port" `Quick
        test_passive_with_sync_port;
      Alcotest.test_case "passive_with_members" `Quick test_passive_with_members;
      Alcotest.test_case "active_requires_async" `Quick
        test_active_requires_async;
      Alcotest.test_case "queued_requires_async" `Quick
        test_queued_requires_async;
      Alcotest.test_case "async_port_in_passive" `Quick
        test_async_port_in_passive;
      Alcotest.test_case "internal_port_in_passive" `Quick
        test_internal_port_in_passive;
      Alcotest.test_case "async_command_in_passive" `Quick
        test_async_command_in_passive;
      Alcotest.test_case "command_negative_opcode" `Quick
        test_command_negative_opcode;
      Alcotest.test_case "event_format_mismatch" `Quick
        test_event_format_mismatch;
      Alcotest.test_case "undefined_type" `Quick test_undefined_type;
      Alcotest.test_case "duplicate_command_opcode" `Quick
        test_duplicate_command_opcode;
    ] )

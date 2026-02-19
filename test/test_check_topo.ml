(** Tests for {!Check_topo}: component instance and topology validation.

    Exercises instance property checks, base ID validation, topology member
    references, and duplicate detection through the public {!Fpp.Check} API.
    Derived from upstream [component_instance_def/] and [top_import/] tests. *)

open Check_test_helpers

(* ── Instance pass cases ─────────────────────────────────────────────── *)

let test_passive_instance () =
  expect_no_errors
    {|
    passive component C { }
    instance c: C base id 0x100
  |}

let test_topology_with_instance () =
  expect_no_errors
    {|
    passive component C { }
    instance c: C base id 0x100
    topology T { instance c }
  |}

(* ── Instance property requirements ──────────────────────────────────── *)

let test_undefined_component () =
  expect_error ~substr:"undefined component"
    {| instance c: Nonexistent base id 0x100 |}

let test_passive_cannot_have_cpu () =
  expect_error ~substr:"cannot have cpu"
    {|
    passive component C { }
    instance c: C base id 0x100 \
      cpu 0
  |}

let test_passive_cannot_have_queue_size () =
  expect_error ~substr:"cannot have queue size"
    {|
    passive component C { }
    instance c: C base id 0x100 \
      queue size 10
  |}

let test_passive_cannot_have_stack_size () =
  expect_error ~substr:"cannot have stack size"
    {|
    passive component C { }
    instance c: C base id 0x100 \
      stack size 1024
  |}

let test_passive_cannot_have_priority () =
  expect_error ~substr:"cannot have priority"
    {|
    passive component C { }
    instance c: C base id 0x100 \
      priority 3
  |}

(* ── Base ID validation ──────────────────────────────────────────────── *)

let test_negative_base_id () =
  expect_error ~substr:"negative base ID"
    {|
    passive component C { }
    instance c: C base id -1
  |}

(* ── Topology duplicate detection ────────────────────────────────────── *)

let test_duplicate_instance_in_topology () =
  expect_error ~substr:"duplicate instance"
    {|
    passive component C { }
    instance c: C base id 0x100
    topology T {
      instance c
      instance c
    }
  |}

let test_duplicate_topology_import () =
  expect_error ~substr:"duplicate import"
    {|
    topology A { }
    topology B {
      import A
      import A
    }
  |}

let test_undefined_topology_import () =
  expect_error ~substr:"undefined"
    {|
    topology B {
      import Nonexistent
    }
  |}

let suite =
  ( "check_topo",
    [
      Alcotest.test_case "passive_instance" `Quick test_passive_instance;
      Alcotest.test_case "topology_with_instance" `Quick
        test_topology_with_instance;
      Alcotest.test_case "undefined_component" `Quick test_undefined_component;
      Alcotest.test_case "passive_cannot_have_cpu" `Quick
        test_passive_cannot_have_cpu;
      Alcotest.test_case "passive_cannot_have_queue_size" `Quick
        test_passive_cannot_have_queue_size;
      Alcotest.test_case "passive_cannot_have_stack_size" `Quick
        test_passive_cannot_have_stack_size;
      Alcotest.test_case "passive_cannot_have_priority" `Quick
        test_passive_cannot_have_priority;
      Alcotest.test_case "negative_base_id" `Quick test_negative_base_id;
      Alcotest.test_case "duplicate_instance_in_topology" `Quick
        test_duplicate_instance_in_topology;
      Alcotest.test_case "duplicate_topology_import" `Quick
        test_duplicate_topology_import;
      Alcotest.test_case "undefined_topology_import" `Quick
        test_undefined_topology_import;
    ] )

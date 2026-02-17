(** Tests for {!Fpp.Ast}. *)

open Fpp

let test_qual_ident_to_string () =
  let loc = Ast.dummy_loc in
  let id name = Ast.node loc name in
  let qi = Ast.Unqualified (id "Foo") in
  Alcotest.(check string) "unqualified" "Foo" (Ast.qual_ident_to_string qi);
  let qi2 = Ast.Qualified (Ast.node loc qi, id "Bar") in
  Alcotest.(check string) "qualified" "Foo.Bar" (Ast.qual_ident_to_string qi2)

let test_qual_ident_roundtrip () =
  let loc = Ast.dummy_loc in
  let ids = [ Ast.node loc "A"; Ast.node loc "B"; Ast.node loc "C" ] in
  let qi = Ast.qual_ident_of_list ids in
  let ids' = Ast.qual_ident_to_list qi in
  Alcotest.(check int) "length" 3 (List.length ids');
  Alcotest.(check string) "first" "A" (Ast.unnode (List.nth ids' 0));
  Alcotest.(check string) "second" "B" (Ast.unnode (List.nth ids' 1));
  Alcotest.(check string) "third" "C" (Ast.unnode (List.nth ids' 2))

let test_annotate () =
  let x = Ast.annotate ~pre:[ "doc" ] ~post:[ "end" ] 42 in
  Alcotest.(check int) "value" 42 (Ast.unannotate x)

let suite =
  ( "ast",
    [
      Alcotest.test_case "qual_ident_to_string" `Quick test_qual_ident_to_string;
      Alcotest.test_case "qual_ident_roundtrip" `Quick test_qual_ident_roundtrip;
      Alcotest.test_case "annotate" `Quick test_annotate;
    ] )

(** Shared test utilities for {!Fpp.Check} tests. *)

let parse s =
  match Fpp.parse_string s with
  | tu -> tu
  | exception Fpp.Parse_error e ->
      Alcotest.failf "parse error: %a" Fpp.pp_error e

let diags s = Fpp.Check.run Fpp.Check.default (parse s)

let errors s =
  diags s |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)

let warnings s =
  diags s
  |> List.filter (fun (d : Fpp.Check.diagnostic) -> d.severity = `Warning)

let msg_contains ~substr msg =
  let len = String.length substr in
  let mlen = String.length msg in
  if len > mlen then false
  else
    let found = ref false in
    for i = 0 to mlen - len do
      if String.sub msg i len = substr then found := true
    done;
    !found

let format_diags ds =
  String.concat "; " (List.map (fun (d : Fpp.Check.diagnostic) -> d.msg) ds)

let expect_error ~substr s =
  let errs = errors s in
  if
    not
      (List.exists
         (fun (d : Fpp.Check.diagnostic) -> msg_contains ~substr d.msg)
         errs)
  then
    Alcotest.failf "expected error containing %S, got: [%s]" substr
      (format_diags errs)

let expect_no_errors s =
  let errs = errors s in
  if errs <> [] then
    Alcotest.failf "expected no errors, got: [%s]" (format_diags errs)

let expect_warning ~substr s =
  let ws = warnings s in
  if
    not
      (List.exists
         (fun (d : Fpp.Check.diagnostic) -> msg_contains ~substr d.msg)
         ws)
  then
    Alcotest.failf "expected warning containing %S, got: [%s]" substr
      (format_diags ws)

let expect_no_warnings s =
  let ws = warnings s in
  if ws <> [] then
    Alcotest.failf "expected no warnings, got: [%s]" (format_diags ws)

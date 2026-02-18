(** ofpp - OCaml FPP analysis toolkit. *)

open Cmdliner

(* --- Output helpers --- *)

let pp_ok ppf () = Fmt.pf ppf "%a" Fmt.(styled `Green string) "✓"
let pp_err ppf () = Fmt.pf ppf "%a" Fmt.(styled `Red string) "✗"
let pp_warn ppf () = Fmt.pf ppf "%a" Fmt.(styled `Yellow string) "!"

(* --- check command --- *)

let check ~verbose files =
  let ok = ref 0 in
  let fail = ref 0 in
  List.iter
    (fun file ->
      match Fpp.parse_file file with
      | tu ->
          let diags = Fpp.Check.run tu in
          let errors =
            List.filter
              (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)
              diags
          in
          if errors <> [] then (
            incr fail;
            List.iter
              (fun d -> Fmt.epr "%a %a@." pp_err () Fpp.Check.pp_diagnostic d)
              errors)
          else
            let warnings =
              List.filter
                (fun (d : Fpp.Check.diagnostic) -> d.severity = `Warning)
                diags
            in
            List.iter
              (fun d -> Fmt.pr "%a %a@." pp_warn () Fpp.Check.pp_diagnostic d)
              warnings;
            incr ok;
            if verbose then
              let comps = Fpp.components tu in
              let sms = Fpp.state_machines tu in
              let topos = Fpp.topologies tu in
              Fmt.pr "%a %s (%d component%s, %d state machine%s, %d topology)@."
                pp_ok () file (List.length comps)
                (if List.length comps <> 1 then "s" else "")
                (List.length sms)
                (if List.length sms <> 1 then "s" else "")
                (List.length topos)
            else Fmt.pr "%a %s@." pp_ok () file
      | exception Fpp.Parse_error e ->
          incr fail;
          Fmt.epr "%a %a@." pp_err () Fpp.pp_error e)
    files;
  if !fail > 0 then (
    Fmt.pr "@.%a %d/%d file%s failed@." pp_err () !fail (!ok + !fail)
      (if !ok + !fail <> 1 then "s" else "");
    1)
  else (
    if List.length files > 1 then
      Fmt.pr "@.%a %d file%s ok@." pp_ok () !ok (if !ok <> 1 then "s" else "");
    0)

let verbose_t =
  Arg.(value & flag & info [ "v"; "verbose" ] ~doc:"Show detailed output.")

let files_t =
  Arg.(
    non_empty & pos_all file []
    & info [] ~docv:"FILE" ~doc:"FPP files to check.")

let check_term =
  let check verbose files = check ~verbose files in
  Term.(const check $ verbose_t $ files_t)

let check_cmd =
  let info =
    Cmd.info "check" ~doc:"Parse and validate FPP files."
      ~man:
        [
          `S "DESCRIPTION";
          `P
            "Parse one or more FPP files and report any syntax or semantic \
             errors. Runs static analysis on state machines to detect \
             duplicate names, missing initial transitions, undefined \
             references, unreachable states, and choice cycles.";
          `S "EXAMPLES";
          `P "$(iname) Components/**/*.fpp";
        ]
  in
  Cmd.v info check_term

(* --- main --- *)

let cmd =
  let info =
    Cmd.info "ofpp" ~version:"%%VERSION%%"
      ~doc:"Static analysis and test generation for F Prime FPP models."
      ~man:
        [
          `S "DESCRIPTION";
          `P
            "ofpp analyses FPP (F Prime Prime) models for NASA's F Prime \
             flight software framework. It provides an FPP parser, static \
             analysis, and test generation.";
          `S "SEE ALSO";
          `P "$(b,https://nasa.github.io/fpp/fpp-users-guide.html)";
        ]
  in
  Cmd.group info [ check_cmd ]

let () =
  match Cmd.eval_value cmd with
  | Ok (`Ok exit_code) -> exit exit_code
  | Ok `Help | Ok `Version -> exit 0
  | Error _ -> exit 1

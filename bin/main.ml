(** ofpp - OCaml FPP analysis toolkit. *)

open Cmdliner

(* --- Output helpers --- *)

let ok_style = Tty.Style.(bold + fg Tty.Color.green)
let err_style = Tty.Style.(bold + fg Tty.Color.red)
let warn_style = Tty.Style.(bold + fg Tty.Color.yellow)
let pp_ok ppf () = Fmt.pf ppf "%a" (Tty.Style.styled ok_style Fmt.string) "✓"
let pp_err ppf () = Fmt.pf ppf "%a" (Tty.Style.styled err_style Fmt.string) "✗"

let pp_warn ppf () =
  Fmt.pf ppf "%a" (Tty.Style.styled warn_style Fmt.string) "!"

(* --- Warnings table --- *)

let pp_warnings_table ppf (warnings : Fpp.Check.diagnostic list) =
  (* Measure the fixed columns to give the Warning column the remaining space *)
  let max_loc, max_name =
    List.fold_left
      (fun (ml, mn) (d : Fpp.Check.diagnostic) ->
        let loc = Fmt.str "%s:%d:%d" d.loc.file d.loc.line d.loc.col in
        (max ml (String.length loc), max mn (String.length d.sm_name)))
      (String.length "Location", String.length "SM")
      warnings
  in
  (* 3 (icon col) + 3*3 (separators) + 2 (borders) = 14 chars of overhead *)
  let used = 14 + max_loc + max_name in
  let warn_max = max 30 (Tty.terminal_width () - used) in
  let columns =
    Tty.Table.
      [
        column ~style:warn_style "";
        column "Location";
        column "SM";
        column ~max_width:warn_max ~overflow:`Wrap "Warning";
      ]
  in
  let rows =
    List.map
      (fun (d : Fpp.Check.diagnostic) ->
        [
          Tty.Span.text "!";
          Tty.Span.text (Fmt.str "%s:%d:%d" d.loc.file d.loc.line d.loc.col);
          Tty.Span.text d.sm_name;
          Tty.Span.text d.msg;
        ])
      warnings
  in
  let table = Tty.Table.of_rows ~border:Tty.Border.rounded columns rows in
  Fmt.pf ppf "%a@." Tty.Table.pp table

let pp_warnings ppf (warnings : Fpp.Check.diagnostic list) =
  match warnings with
  | [] -> ()
  | [ w ] -> Fmt.pf ppf "%a %a@." pp_warn () Fpp.Check.pp_diagnostic w
  | _ -> pp_warnings_table ppf warnings

(* --- check command --- *)

type file_result = {
  file : string;
  status : [ `Ok | `Fail ];
  components : int;
  state_machines : int;
  topologies : int;
  warnings : int;
}

let check_file config file =
  match Fpp.parse_file file with
  | tu ->
      let diags = Fpp.Check.run config tu in
      let errors =
        List.filter
          (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)
          diags
      in
      if errors <> [] then (
        List.iter
          (fun d -> Fmt.epr "%a %a@." pp_err () Fpp.Check.pp_diagnostic d)
          errors;
        {
          file;
          status = `Fail;
          components = 0;
          state_machines = 0;
          topologies = 0;
          warnings = 0;
        })
      else
        let warnings =
          List.filter
            (fun (d : Fpp.Check.diagnostic) -> d.severity = `Warning)
            diags
        in
        pp_warnings Fmt.stdout warnings;
        let comps = Fpp.components tu in
        let sms = Fpp.state_machines tu in
        let topos = Fpp.topologies tu in
        {
          file;
          status = `Ok;
          components = List.length comps;
          state_machines = List.length sms;
          topologies = List.length topos;
          warnings = List.length warnings;
        }
  | exception Fpp.Parse_error e ->
      Fmt.epr "%a %a@." pp_err () Fpp.pp_error e;
      {
        file;
        status = `Fail;
        components = 0;
        state_machines = 0;
        topologies = 0;
        warnings = 0;
      }

let pp_summary_table ppf results =
  let columns =
    Tty.Table.
      [
        column "";
        column "File";
        column ~align:`Right "Components";
        column ~align:`Right "State Machines";
        column ~align:`Right "Topologies";
        column ~align:`Right "Warnings";
      ]
  in
  let rows =
    List.map
      (fun r ->
        let icon, style =
          match r.status with
          | `Ok -> ("✓", ok_style)
          | `Fail -> ("✗", err_style)
        in
        let warn_cell =
          if r.warnings > 0 then
            Tty.Span.styled warn_style (string_of_int r.warnings)
          else Tty.Span.text "0"
        in
        [
          Tty.Span.styled style icon;
          Tty.Span.text r.file;
          Tty.Span.text (string_of_int r.components);
          Tty.Span.text (string_of_int r.state_machines);
          Tty.Span.text (string_of_int r.topologies);
          warn_cell;
        ])
      results
  in
  let table = Tty.Table.of_rows ~border:Tty.Border.rounded columns rows in
  Fmt.pf ppf "@.%a" Tty.Table.pp table

let pp_file_result ~verbose r =
  if r.status = `Fail then ()
  else if verbose then
    Fmt.pr "%a %s (%d component%s, %d state machine%s, %d topolog%s)@." pp_ok ()
      r.file r.components
      (if r.components <> 1 then "s" else "")
      r.state_machines
      (if r.state_machines <> 1 then "s" else "")
      r.topologies
      (if r.topologies <> 1 then "ies" else "y")
  else Fmt.pr "%a %s@." pp_ok () r.file

let check ~verbose ~skip files =
  let config =
    List.fold_left
      (fun c name ->
        match Fpp.Check.analysis_of_string name with
        | Some a -> Fpp.Check.skip [ a ] c
        | None -> c)
      Fpp.Check.default skip
  in
  let results = List.map (check_file config) files in
  let multi = List.length files > 1 in
  if verbose && multi then pp_summary_table Fmt.stdout results
  else List.iter (pp_file_result ~verbose) results;
  let n_ok = List.length (List.filter (fun r -> r.status = `Ok) results) in
  let n_fail = List.length (List.filter (fun r -> r.status = `Fail) results) in
  if n_fail > 0 then (
    Fmt.pr "@.%a %d/%d file%s failed@." pp_err () n_fail (n_ok + n_fail)
      (if n_ok + n_fail <> 1 then "s" else "");
    1)
  else (
    if multi then
      Fmt.pr "@.%a %d file%s ok@." pp_ok () n_ok (if n_ok <> 1 then "s" else "");
    0)

(* --- cmdliner terms --- *)

let verbose_t =
  Arg.(value & flag & info [ "v"; "verbose" ] ~doc:"Show detailed output.")

let skip_t =
  let analysis_names = Fpp.Check.analyses in
  let doc =
    Fmt.str "Skip an analysis. May be repeated. $(docv) is one of %s."
      (Arg.doc_alts analysis_names)
  in
  Arg.(
    value
    & opt_all (enum (List.map (fun a -> (a, a)) analysis_names)) []
    & info [ "skip" ] ~doc ~docv:"ANALYSIS")

let files_t =
  Arg.(
    non_empty & pos_all file []
    & info [] ~docv:"FILE" ~doc:"FPP files to check.")

let check_term =
  let check verbose skip files = check ~verbose ~skip files in
  Term.(const check $ verbose_t $ skip_t $ files_t)

let check_cmd =
  let info =
    Cmd.info "check" ~doc:"Parse and validate FPP files."
      ~man:
        [
          `S "DESCRIPTION";
          `P
            "Parse one or more FPP files and run static analysis. Reports \
             errors (duplicate names, missing initial transitions, undefined \
             references, unreachable states, choice cycles, type mismatches) \
             and warnings (signal coverage gaps, liveness issues).";
          `P
            "All analyses run by default. Use $(b,--skip) to disable specific \
             warning-level analyses.";
          `S "EXAMPLES";
          `P "$(iname) Components/**/*.fpp";
          `P "$(iname) --skip coverage model.fpp";
        ]
  in
  Cmd.v info check_term

(* --- dot command --- *)

type graph_format = Dot | D2

let dot ~format ~sm_name files =
  let pp = match format with Dot -> Fpp.Dot.pp | D2 -> Fpp.D2.pp in
  let ok = ref true in
  List.iter
    (fun file ->
      match Fpp.parse_file file with
      | tu ->
          let sms = Fpp.state_machines tu in
          let sms =
            match sm_name with
            | None -> sms
            | Some name ->
                List.filter
                  (fun (sm : Fpp.Ast.def_state_machine) ->
                    sm.sm_name.data = name)
                  sms
          in
          List.iter (fun sm -> pp Fmt.stdout sm) sms
      | exception Fpp.Parse_error e ->
          Fmt.epr "%a %a@." pp_err () Fpp.pp_error e;
          ok := false)
    files;
  if !ok then 0 else 1

let format_t =
  let doc =
    "Output format. $(docv) is one of $(b,dot) (Graphviz DOT) or $(b,d2) (D2 \
     diagramming language)."
  in
  Arg.(
    value
    & opt (enum [ ("dot", Dot); ("d2", D2) ]) Dot
    & info [ "f"; "format" ] ~doc ~docv:"FORMAT")

let sm_name_t =
  Arg.(
    value
    & opt (some string) None
    & info [ "sm" ] ~docv:"NAME"
        ~doc:"Only output the state machine named $(docv).")

let dot_files_t =
  Arg.(
    non_empty & pos_all file []
    & info [] ~docv:"FILE" ~doc:"FPP files to render.")

let dot_term =
  let dot format sm_name files = dot ~format ~sm_name files in
  Term.(const dot $ format_t $ sm_name_t $ dot_files_t)

let dot_cmd =
  let info =
    Cmd.info "dot" ~doc:"Render state machines as diagrams."
      ~man:
        [
          `S "DESCRIPTION";
          `P
            "Parse FPP files and output diagrams for each state machine. \
             Supports Graphviz DOT (default) and D2 output formats.";
          `S "EXAMPLES";
          `P "$(iname) model.fpp | dot -Tpng -o sm.png";
          `P "$(iname) -f d2 model.fpp | d2 - sm.svg";
          `P "$(iname) --sm M model.fpp | dot -Tsvg -o M.svg";
        ]
  in
  Cmd.v info dot_term

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
  Cmd.group info [ check_cmd; dot_cmd ]

let () =
  match Cmd.eval_value cmd with
  | Ok (`Ok exit_code) -> exit exit_code
  | Ok `Help | Ok `Version -> exit 0
  | Error _ -> exit 1

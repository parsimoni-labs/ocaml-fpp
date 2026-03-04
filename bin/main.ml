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
      let warnings =
        List.filter
          (fun (d : Fpp.Check.diagnostic) -> d.severity = `Warning)
          diags
      in
      pp_warnings Fmt.stdout warnings;
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
          warnings = List.length warnings;
        })
      else
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

(* --- cmdliner terms --- *)

let verbose_t =
  Arg.(value & flag & info [ "v"; "verbose" ] ~doc:"Show detailed output.")

let spec_conv =
  let parse s =
    match Fpp.Check.parse_spec s with
    | Ok ds -> Ok ds
    | Error msg -> Error (`Msg msg)
  in
  let pp ppf ds =
    let pp_directive ppf = function
      | Fpp.Check.Enable a -> Fmt.pf ppf "+%s" (Fpp.Check.string_of_analysis a)
      | Fpp.Check.Disable a -> Fmt.pf ppf "-%s" (Fpp.Check.string_of_analysis a)
      | Fpp.Check.Enable_all -> Fmt.string ppf "+all"
      | Fpp.Check.Disable_all -> Fmt.string ppf "-all"
    in
    Fmt.(list ~sep:comma pp_directive) ppf ds
  in
  Arg.conv (parse, pp)

let warning_spec_t =
  let doc =
    "Warning specification. Comma-separated list of analyses to enable or \
     disable. Prefix with $(b,-) to disable, $(b,+) or bare name to enable. \
     Use $(b,all) or $(b,A) for all analyses. Names: $(b,coverage) ($(b,cov)), \
     $(b,liveness) ($(b,liv)), $(b,unused) ($(b,unu)), $(b,shadowing) \
     ($(b,sha)), $(b,deadlock) ($(b,dea)), $(b,completeness) ($(b,com)), \
     $(b,unconnected) ($(b,unc)), $(b,sync_cycle) ($(b,syn))."
  in
  let open Arg in
  value & opt_all spec_conv [] & info [ "w"; "warning" ] ~doc ~docv:"SPEC"

let error_spec_t =
  let doc =
    "Error promotion specification. Same syntax as $(b,-w). Promotes enabled \
     analyses to error level, causing a non-zero exit code when triggered. An \
     analysis disabled by $(b,-w) cannot be promoted."
  in
  let open Arg in
  value & opt_all spec_conv [] & info [ "e"; "error" ] ~doc ~docv:"SPEC"

(* --- dot command --- *)

let image_extensions = [ ".svg"; ".png"; ".pdf" ]

let is_image_output path =
  let ext = Filename.extension path in
  List.mem (String.lowercase_ascii ext) image_extensions

let run_dot dot_text output_path =
  let ext = String.lowercase_ascii (Filename.extension output_path) in
  let fmt = match ext with ".png" -> "png" | ".pdf" -> "pdf" | _ -> "svg" in
  let cmd =
    Fmt.str "dot -T%s -o %s 2>/dev/null" fmt (Filename.quote output_path)
  in
  let oc = Unix.open_process_out cmd in
  output_string oc dot_text;
  match Unix.close_process_out oc with
  | Unix.WEXITED 0 -> true
  | _ ->
      Fmt.epr "%a dot failed to render %s@." pp_err () output_path;
      false

let emit_dot_text output ok dot_text =
  match output with
  | Some path when is_image_output path ->
      if not (run_dot dot_text path) then ok := false
  | Some path ->
      let oc = open_out path in
      Fun.protect
        ~finally:(fun () -> close_out oc)
        (fun () -> output_string oc dot_text)
  | None -> Fmt.pr "%s" dot_text

let dot_render_sms buf ppf output ok tu ~sm_name =
  let sms = Fpp.state_machines tu in
  let sms =
    match sm_name with
    | None -> sms
    | Some name ->
        List.filter
          (fun (sm : Fpp.Ast.def_state_machine) -> sm.sm_name.data = name)
          sms
  in
  List.iter
    (fun sm ->
      Buffer.clear buf;
      Fpp.Dot.pp ppf sm;
      Fmt.flush ppf ();
      emit_dot_text output ok (Buffer.contents buf))
    sms

let dot_render_topos buf ppf output ok tu ~topo_name =
  let topos = Fpp.topologies tu in
  let topos =
    match topo_name with
    | None -> topos
    | Some name ->
        List.filter
          (fun (t : Fpp.Ast.def_topology) -> t.topo_name.data = name)
          topos
  in
  List.iter
    (fun topo ->
      Buffer.clear buf;
      Fpp.Dot.pp_topology tu ppf topo;
      Fmt.flush ppf ();
      emit_dot_text output ok (Buffer.contents buf))
    topos

let parse_files files =
  let tus = ref [] in
  let ok = ref true in
  List.iter
    (fun file ->
      match Fpp.parse_file file with
      | tu -> tus := (file, tu) :: !tus
      | exception Fpp.Parse_error e ->
          Fmt.epr "%a %a@." pp_err () Fpp.pp_error e;
          ok := false)
    files;
  if not !ok then None else Some (List.rev !tus)

let merge_tus per_file =
  let members =
    List.concat_map
      (fun (_, (tu : Fpp.Ast.translation_unit)) -> tu.tu_members)
      per_file
  in
  { Fpp.Ast.tu_members = members }

let check_merged config files =
  match parse_files files with
  | None -> 1
  | Some per_file ->
      let tu = merge_tus per_file in
      let diags = Fpp.Check.run config tu in
      let errors =
        List.filter
          (fun (d : Fpp.Check.diagnostic) -> d.severity = `Error)
          diags
      in
      let warnings =
        List.filter
          (fun (d : Fpp.Check.diagnostic) -> d.severity = `Warning)
          diags
      in
      pp_warnings Fmt.stdout warnings;
      if errors <> [] then (
        List.iter
          (fun d -> Fmt.epr "%a %a@." pp_err () Fpp.Check.pp_diagnostic d)
          errors;
        let file_set =
          List.fold_left
            (fun acc (d : Fpp.Check.diagnostic) ->
              if List.mem d.loc.file acc then acc else d.loc.file :: acc)
            [] errors
          |> List.rev
        in
        Fmt.pr "@.%a %d/%d file%s failed@." pp_err () (List.length file_set)
          (List.length files)
          (if List.length files <> 1 then "s" else "");
        1)
      else (
        List.iter (fun (file, _) -> Fmt.pr "%a %s@." pp_ok () file) per_file;
        if List.length files > 1 then
          Fmt.pr "@.%a %d files ok@." pp_ok () (List.length files);
        0)

let check ~verbose ~warning_spec ~error_spec files =
  let config = Fpp.Check.config ~warning_spec ~error_spec in
  match files with
  | [ _ ] ->
      let results = List.map (check_file config) files in
      List.iter (pp_file_result ~verbose) results;
      let n_fail =
        List.length (List.filter (fun r -> r.status = `Fail) results)
      in
      if n_fail > 0 then (
        Fmt.pr "@.%a 1/1 file failed@." pp_err ();
        1)
      else 0
  | _ -> check_merged config files

let check_files_t =
  Arg.(
    non_empty & pos_all file []
    & info [] ~docv:"FILE" ~doc:"FPP files to check.")

let check_term =
  let run verbose warning_specs error_specs files =
    let warning_spec = List.concat warning_specs in
    let error_spec = List.concat error_specs in
    check ~verbose ~warning_spec ~error_spec files
  in
  Term.(const run $ verbose_t $ warning_spec_t $ error_spec_t $ check_files_t)

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
            "When multiple files are given, they are merged into a single \
             translation unit before checking, so cross-file references \
             resolve correctly.";
          `P
            "All warning-level analyses run by default. Use $(b,-w) to \
             selectively enable or disable analyses, and $(b,-e) to promote \
             warnings to errors.";
          `S "EXAMPLES";
          `P "$(iname) Components/**/*.fpp";
          `P "$(iname) -w -cov model.fpp";
          `Noblank;
          `Pre "  Disable the coverage analysis.";
          `P "$(iname) -e all model.fpp";
          `Noblank;
          `Pre "  Promote all warnings to errors.";
          `P "$(iname) -w -all,+deadlock model.fpp";
          `Noblank;
          `Pre "  Only run the deadlock analysis.";
          `P "$(iname) -e cov,dea -w -sha model.fpp";
          `Noblank;
          `Pre "  Promote coverage and deadlock to errors, disable shadowing.";
        ]
  in
  Cmd.v info check_term

(* --- dot command --- *)

let dot ~output ~sm_name ~topo_name files =
  if sm_name <> None && topo_name <> None then begin
    Fmt.epr "%a --sm and --topology are mutually exclusive@." pp_err ();
    1
  end
  else
    match parse_files files with
    | None -> 1
    | Some per_file ->
        let merged = merge_tus per_file in
        let ok = ref true in
        let buf = Buffer.create 4096 in
        let ppf = Fmt.with_buffer buf in
        List.iter
          (fun (_file, tu) ->
            if topo_name = None then
              dot_render_sms buf ppf output ok tu ~sm_name)
          per_file;
        if sm_name = None then
          dot_render_topos buf ppf output ok merged ~topo_name;
        if !ok then 0 else 1

let output_t =
  let doc =
    "Output file. For image formats ($(b,.svg), $(b,.png), $(b,.pdf)), invokes \
     $(b,dot) automatically. For other extensions, writes DOT text. If \
     omitted, DOT text is written to stdout."
  in
  Arg.(
    value & opt (some string) None & info [ "o"; "output" ] ~doc ~docv:"FILE")

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

let topo_name_t =
  Arg.(
    value
    & opt (some string) None
    & info [ "topology" ] ~docv:"NAME"
        ~doc:"Only output the topology named $(docv).")

let dot_term =
  let dot output sm_name topo_name files =
    dot ~output ~sm_name ~topo_name files
  in
  Term.(const dot $ output_t $ sm_name_t $ topo_name_t $ dot_files_t)

let dot_cmd =
  let info =
    Cmd.info "dot" ~doc:"Render state machines and topologies as diagrams."
      ~man:
        [
          `S "DESCRIPTION";
          `P
            "Parse FPP files and output state machine and topology diagrams in \
             Graphviz DOT format. With $(b,-o), renders directly to SVG, PNG, \
             or PDF (requires $(b,dot) to be installed).";
          `P
            "By default, all state machines and topologies are rendered. Use \
             $(b,--sm) to render only a named state machine, or \
             $(b,--topology) to render only a named topology.";
          `S "EXAMPLES";
          `P "$(iname) model.fpp                    # DOT to stdout";
          `P "$(iname) -o sm.svg model.fpp          # render to SVG";
          `P "$(iname) --topology T model.fpp       # topology only";
          `P "$(iname) --sm M model.fpp             # state machine only";
          `P "$(iname) model.fpp | dot -Tsvg -o sm.svg  # manual pipe";
        ]
  in
  Cmd.v info dot_term

(* --- to-ml command --- *)

let write_output output text =
  match output with
  | Some path ->
      let oc = open_out path in
      Fun.protect
        ~finally:(fun () -> close_out oc)
        (fun () -> output_string oc text)
  | None -> print_string text

let pp_wrapped_topo ppf tu ~wrap t =
  if Fpp.Gen_ml.topology_has_output tu t then begin
    if wrap then
      Fmt.pf ppf "@[<v>module %s = struct@,"
        (String.capitalize_ascii (t : Fpp.Ast.def_topology).topo_name.data);
    Fpp.Gen_ml.pp_topology tu ppf t;
    if wrap then Fmt.pf ppf "end@]@."
  end

let mli_path_of ml_path =
  if Filename.check_suffix ml_path ".ml" then
    Filename.chop_suffix ml_path ".ml" ^ ".mli"
  else ml_path ^ "i"

let trim_trailing_newlines s =
  let n = String.length s in
  let i = ref (n - 1) in
  while !i >= 0 && (s.[!i] = '\n' || s.[!i] = ' ') do
    decr i
  done;
  String.sub s 0 (!i + 1) ^ "\n"

let gen_ml_topologies ppf tu topologies =
  let all_topos = Fpp.topologies tu in
  let topos =
    List.filter
      (fun (t : Fpp.Ast.def_topology) -> List.mem t.topo_name.data topologies)
      all_topos
  in
  let wrap = List.length topos > 1 in
  List.iter (pp_wrapped_topo ppf tu ~wrap) topos;
  let entry_names =
    List.concat_map
      (fun (t : Fpp.Ast.def_topology) ->
        if Fpp.Gen_ml.topology_is_fully_bound tu t then
          let prefix =
            if wrap then String.capitalize_ascii t.topo_name.data ^ "." else ""
          in
          List.map
            (fun (var, mod_name) -> (prefix ^ var, prefix ^ mod_name))
            (Fpp.Gen_ml.topology_active_instance_names tu t)
        else [])
      topos
  in
  if entry_names <> [] then begin
    let entry_topos =
      List.filter
        (fun (t : Fpp.Ast.def_topology) ->
          Fpp.Gen_ml.topology_is_fully_bound tu t)
        topos
    in
    let topo_name =
      String.concat "+"
        (List.map
           (fun (t : Fpp.Ast.def_topology) -> t.topo_name.data)
           entry_topos)
    in
    Fpp.Gen_ml.pp_entry_point ppf ~topo_name entry_names
  end

let gen_mli_topologies ppf tu topologies =
  let all_topos = Fpp.topologies tu in
  let topos =
    List.filter
      (fun (t : Fpp.Ast.def_topology) -> List.mem t.topo_name.data topologies)
      all_topos
  in
  let wrap = List.length topos > 1 in
  List.iter
    (fun t ->
      if Fpp.Gen_ml.topology_has_output tu t then begin
        if wrap then
          Fmt.pf ppf "@[<v>module %s : sig@,"
            (String.capitalize_ascii (t : Fpp.Ast.def_topology).topo_name.data);
        Fpp.Gen_ml.pp_topology_mli tu ppf t;
        if wrap then Fmt.pf ppf "end@]@."
      end)
    topos

let gen_ml_all ppf tu ~sm_name =
  let sms = Fpp.state_machines tu in
  let sms =
    match sm_name with
    | None -> sms
    | Some name ->
        List.filter
          (fun (sm : Fpp.Ast.def_state_machine) -> sm.sm_name.data = name)
          sms
  in
  let topos = Fpp.topologies tu in
  let wrap = List.length sms + List.length topos > 1 in
  List.iter
    (fun (sm : Fpp.Ast.def_state_machine) ->
      if wrap then
        Fmt.pf ppf "@[<v>module %s = struct@,"
          (String.capitalize_ascii sm.sm_name.data);
      Fpp.Gen_ml.pp ppf sm;
      if wrap then Fmt.pf ppf "end@]@.")
    sms;
  List.iter (pp_wrapped_topo ppf tu ~wrap) topos

let gen_ml_for_tu ppf tu ~sm_name ~topologies =
  if topologies <> [] then gen_ml_topologies ppf tu topologies
  else gen_ml_all ppf tu ~sm_name

let to_ml ~output ~sm_name ~topologies files =
  match parse_files files with
  | None -> 1
  | Some per_file ->
      let tu = merge_tus per_file in
      let buf = Buffer.create 4096 in
      let ppf = Fmt.with_buffer buf in
      Fmt.pf ppf "[@@@@@@ocamlformat \"disable\"]@.";
      gen_ml_for_tu ppf tu ~sm_name ~topologies;
      Fmt.flush ppf ();
      let text = Buffer.contents buf in
      if text <> "" then write_output output text;
      (* Generate .mli when writing to a file and topologies are specified *)
      (match output with
      | Some path when topologies <> [] ->
          let buf = Buffer.create 4096 in
          let ppf = Fmt.with_buffer buf in
          Fmt.pf ppf "[@@@@@@ocamlformat \"disable\"]@.";
          gen_mli_topologies ppf tu topologies;
          Fmt.flush ppf ();
          let mli_text = Buffer.contents buf in
          if mli_text <> "" then
            write_output
              (Some (mli_path_of path))
              (trim_trailing_newlines mli_text)
      | _ -> ());
      0

let to_ml_output_t =
  let doc = "Output file. If omitted, OCaml code is written to stdout." in
  Arg.(
    value & opt (some string) None & info [ "o"; "output" ] ~doc ~docv:"FILE")

let to_ml_files_t =
  Arg.(
    non_empty & pos_all file []
    & info [] ~docv:"FILE" ~doc:"FPP files to generate OCaml from.")

let topologies_t =
  let parse s =
    Ok (String.split_on_char ',' s |> List.filter (fun s -> s <> ""))
  in
  let pp ppf names = Fmt.(list ~sep:comma string) ppf names in
  let topo_conv = Arg.conv (parse, pp) in
  Arg.(
    value & opt_all topo_conv []
    & info [ "topologies" ] ~docv:"NAMES"
        ~doc:
          "Output only the named topologies and their entry points. \
           Comma-separated names (e.g. $(b,--topologies T1,T2)). Module prefix \
           for entry points is inferred from the input filename.")

let to_ml_term =
  let to_ml output sm_name topologies_lists files =
    let topologies = List.concat topologies_lists in
    to_ml ~output ~sm_name ~topologies files
  in
  Term.(const to_ml $ to_ml_output_t $ sm_name_t $ topologies_t $ to_ml_files_t)

let to_ml_cmd =
  let info =
    Cmd.info "to-ml"
      ~doc:"Generate OCaml modules from state machines and topologies."
      ~man:
        [
          `S "DESCRIPTION";
          `P
            "Parse FPP files and generate idiomatic OCaml code for state \
             machines and topologies. State machines use GADTs for typed \
             signals, module types for actions and guards, and functors for \
             dependency injection. Topologies become OCaml functors with typed \
             wiring.";
          `S "EXAMPLES";
          `P "$(iname) model.fpp                        # everything to stdout";
          `P
            "$(iname) --topologies T1 model.fpp         # one topology + entry \
             point";
          `P "$(iname) --topologies T1,T2 model.fpp      # multiple topologies";
          `P "$(iname) --sm Thermostat model.fpp        # select one SM";
        ]
  in
  Cmd.v info to_ml_term

(* --- fpv command --- *)

let fpv ~output ~topo_name files =
  match parse_files files with
  | None -> 1
  | Some per_file ->
      let merged = merge_tus per_file in
      let topos = Fpp.topologies merged in
      let topos =
        match topo_name with
        | None -> topos
        | Some name ->
            List.filter
              (fun (t : Fpp.Ast.def_topology) -> t.topo_name.data = name)
              topos
      in
      let ok = ref true in
      let buf = Buffer.create 4096 in
      let ppf = Fmt.with_buffer buf in
      List.iter
        (fun topo ->
          Buffer.clear buf;
          Fpp.Fpv.pp_topology merged ppf topo;
          Fmt.flush ppf ();
          let text = Buffer.contents buf in
          match output with
          | Some path ->
              let oc = open_out path in
              Fun.protect
                ~finally:(fun () -> close_out oc)
                (fun () -> output_string oc text)
          | None -> Fmt.pr "%s" text)
        topos;
      if !ok then 0 else 1

let fpv_output_t =
  let doc = "Output file. If omitted, JSON is written to stdout." in
  Arg.(
    value & opt (some string) None & info [ "o"; "output" ] ~doc ~docv:"FILE")

let fpv_files_t =
  Arg.(
    non_empty & pos_all file []
    & info [] ~docv:"FILE" ~doc:"FPP files to render.")

let fpv_topo_name_t =
  Arg.(
    value
    & opt (some string) None
    & info [ "topology" ] ~docv:"NAME"
        ~doc:"Only output the topology named $(docv).")

let fpv_term =
  let fpv output topo_name files = fpv ~output ~topo_name files in
  Term.(const fpv $ fpv_output_t $ fpv_topo_name_t $ fpv_files_t)

let fpv_cmd =
  let info =
    Cmd.info "fpv" ~doc:"Export topologies as F Prime Visual JSON."
      ~man:
        [
          `S "DESCRIPTION";
          `P
            "Parse FPP files and output topology connection graphs as JSON \
             compatible with fprime-visual, the browser-based F Prime topology \
             visualiser. Instances are laid out in columns using longest-path \
             layering.";
          `S "EXAMPLES";
          `P "$(iname) model.fpp                        # JSON to stdout";
          `P "$(iname) -o topo.json model.fpp           # write to file";
          `P "$(iname) --topology T model.fpp           # one topology only";
        ]
  in
  Cmd.v info fpv_term

(* --- main --- *)

let cmd =
  let info =
    Cmd.info "ofpp" ~version:Git_info.version
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
  Cmd.group info [ check_cmd; dot_cmd; fpv_cmd; to_ml_cmd ]

let () =
  match Cmd.eval_value cmd with
  | Ok (`Ok exit_code) -> exit exit_code
  | Ok `Help | Ok `Version -> exit 0
  | Error _ -> exit 1

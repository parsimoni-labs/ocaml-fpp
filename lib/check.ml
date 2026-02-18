(** State machine static analysis.

    Orchestrates core error checks ({!Check_core}) and optional warning-level
    analyses ({!Check_warn}) over FPP state machines. *)

(* ── Analysis categories ────────────────────────────────────────────── *)

type analysis =
  | Coverage
  | Liveness
  | Unused
  | Shadowing
  | Deadlock
  | Completeness

let all_analyses =
  [ Coverage; Liveness; Unused; Shadowing; Deadlock; Completeness ]

let string_of_analysis = function
  | Coverage -> "coverage"
  | Liveness -> "liveness"
  | Unused -> "unused"
  | Shadowing -> "shadowing"
  | Deadlock -> "deadlock"
  | Completeness -> "completeness"

let analysis_of_string = function
  | "coverage" | "cov" -> Some Coverage
  | "liveness" | "liv" -> Some Liveness
  | "unused" | "unu" -> Some Unused
  | "shadowing" | "sha" -> Some Shadowing
  | "deadlock" | "dea" -> Some Deadlock
  | "completeness" | "com" -> Some Completeness
  | _ -> None

let analyses =
  [ "coverage"; "liveness"; "unused"; "shadowing"; "deadlock"; "completeness" ]

(* ── Severity levels ──────────────────────────────────────────────── *)

type level = Off | Warning | Error

(* ── Warning and error specs ──────────────────────────────────────── *)

type directive =
  | Enable of analysis
  | Disable of analysis
  | Enable_all
  | Disable_all

let parse_one s =
  let s = String.trim s in
  if s = "" then Ok []
  else
    let sign, name =
      if String.length s > 0 && s.[0] = '+' then
        (`Enable, String.sub s 1 (String.length s - 1))
      else if String.length s > 0 && s.[0] = '-' then
        (`Disable, String.sub s 1 (String.length s - 1))
      else (`Enable, s)
    in
    let name = String.trim name in
    if name = "all" || name = "A" then
      match sign with
      | `Enable -> Ok [ Enable_all ]
      | `Disable -> Ok [ Disable_all ]
    else
      match analysis_of_string name with
      | Some a -> (
          match sign with
          | `Enable -> Ok [ Enable a ]
          | `Disable -> Ok [ Disable a ])
      | None -> Error (Fmt.str "unknown analysis '%s'" name)

let parse_spec s =
  let parts = String.split_on_char ',' s in
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | p :: ps -> (
        match parse_one p with
        | Ok ds -> go (List.rev_append ds acc) ps
        | Error _ as e -> e)
  in
  go [] parts

(* ── Configuration ──────────────────────────────────────────────────── *)

type config = {
  coverage : level;
  liveness : level;
  unused : level;
  shadowing : level;
  deadlock : level;
  completeness : level;
}

let default =
  {
    coverage = Warning;
    liveness = Warning;
    unused = Warning;
    shadowing = Warning;
    deadlock = Warning;
    completeness = Warning;
  }

let set_level config analysis level =
  match analysis with
  | Coverage -> { config with coverage = level }
  | Liveness -> { config with liveness = level }
  | Unused -> { config with unused = level }
  | Shadowing -> { config with shadowing = level }
  | Deadlock -> { config with deadlock = level }
  | Completeness -> { config with completeness = level }

let level_of config = function
  | Coverage -> config.coverage
  | Liveness -> config.liveness
  | Unused -> config.unused
  | Shadowing -> config.shadowing
  | Deadlock -> config.deadlock
  | Completeness -> config.completeness

let apply_warning_spec config directives =
  List.fold_left
    (fun c d ->
      match d with
      | Enable a ->
          let cur = level_of c a in
          if cur = Off then set_level c a Warning else c
      | Disable a -> set_level c a Off
      | Enable_all ->
          List.fold_left
            (fun c a ->
              let cur = level_of c a in
              if cur = Off then set_level c a Warning else c)
            c all_analyses
      | Disable_all ->
          List.fold_left (fun c a -> set_level c a Off) c all_analyses)
    config directives

let apply_error_spec config directives =
  List.fold_left
    (fun c d ->
      match d with
      | Enable a ->
          let cur = level_of c a in
          if cur <> Off then set_level c a Error else c
      | Disable a ->
          let cur = level_of c a in
          if cur = Error then set_level c a Warning else c
      | Enable_all ->
          List.fold_left
            (fun c a ->
              let cur = level_of c a in
              if cur <> Off then set_level c a Error else c)
            c all_analyses
      | Disable_all ->
          List.fold_left
            (fun c a ->
              let cur = level_of c a in
              if cur = Error then set_level c a Warning else c)
            c all_analyses)
    config directives

let config ~warning_spec ~error_spec =
  let c = apply_warning_spec default warning_spec in
  apply_error_spec c error_spec

(* ── Re-exported types ──────────────────────────────────────────────── *)

type diagnostic = Check_env.diagnostic = {
  severity : [ `Error | `Warning ];
  loc : Ast.loc;
  sm_name : string;
  msg : string;
}

let pp_diagnostic = Check_env.pp_diagnostic

(* ── Entry points ───────────────────────────────────────────────────── *)

let run_analysis config analysis f =
  match level_of config analysis with
  | Off -> []
  | Warning -> f ()
  | Error ->
      f () |> List.map (fun (d : diagnostic) -> { d with severity = `Error })

let state_machine config (sm : Ast.def_state_machine) =
  let sm_name = sm.sm_name.data in
  match sm.sm_members with
  | None -> []
  | Some members ->
      let env = Check_env.build_sm_env members in
      let core = Check_core.run ~sm_name ~sm_loc:sm.sm_name.loc env members in
      let coverage =
        run_analysis config Coverage (fun () ->
            Check_warn.signal_coverage ~sm_name env members)
      in
      let live =
        run_analysis config Liveness (fun () ->
            Check_warn.liveness ~sm_name members)
      in
      let unused =
        run_analysis config Unused (fun () ->
            Check_warn.unused_declarations ~sm_name env members)
      in
      let shadow =
        run_analysis config Shadowing (fun () ->
            Check_warn.transition_shadowing ~sm_name members)
      in
      let dead =
        run_analysis config Deadlock (fun () ->
            Check_warn.deadlock_states ~sm_name env members)
      in
      let complete =
        run_analysis config Completeness (fun () ->
            Check_warn.guard_completeness ~sm_name members)
      in
      core @ coverage @ live @ unused @ shadow @ dead @ complete

let rec collect_state_machines members =
  List.concat_map
    (fun (_, n, _) ->
      match n.Ast.data with
      | Ast.Mod_def_state_machine sm -> [ sm ]
      | Ast.Mod_def_module m -> collect_state_machines m.Ast.module_members
      | _ -> [])
    members

let run config tu =
  let sms = collect_state_machines tu.Ast.tu_members in
  List.concat_map (state_machine config) sms

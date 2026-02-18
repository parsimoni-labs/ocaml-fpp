(** State machine static analysis.

    Orchestrates core error checks ({!Check_core}) and optional warning-level
    analyses ({!Check_warn}) over FPP state machines. *)

(* ── Analysis categories ────────────────────────────────────────────── *)

type analysis = Coverage | Liveness | Unused | Shadowing | Deadlock

let all_analyses = [ Coverage; Liveness; Unused; Shadowing; Deadlock ]

let analysis_of_string = function
  | "coverage" -> Some Coverage
  | "liveness" -> Some Liveness
  | "unused" -> Some Unused
  | "shadowing" -> Some Shadowing
  | "deadlock" -> Some Deadlock
  | _ -> None

let analyses = [ "coverage"; "liveness"; "unused"; "shadowing"; "deadlock" ]

(* ── Configuration ──────────────────────────────────────────────────── *)

type config = {
  coverage : bool;
  liveness : bool;
  unused : bool;
  shadowing : bool;
  deadlock : bool;
}

let default =
  {
    coverage = true;
    liveness = true;
    unused = true;
    shadowing = true;
    deadlock = true;
  }

let skip analyses config =
  List.fold_left
    (fun c a ->
      match a with
      | Coverage -> { c with coverage = false }
      | Liveness -> { c with liveness = false }
      | Unused -> { c with unused = false }
      | Shadowing -> { c with shadowing = false }
      | Deadlock -> { c with deadlock = false })
    config analyses

(* ── Re-exported types ──────────────────────────────────────────────── *)

type diagnostic = Check_env.diagnostic = {
  severity : [ `Error | `Warning ];
  loc : Ast.loc;
  sm_name : string;
  msg : string;
}

let pp_diagnostic = Check_env.pp_diagnostic

(* ── Entry points ───────────────────────────────────────────────────── *)

let state_machine config (sm : Ast.def_state_machine) =
  let sm_name = sm.sm_name.data in
  match sm.sm_members with
  | None -> []
  | Some members ->
      let env = Check_env.build_sm_env members in
      let core = Check_core.run ~sm_name ~sm_loc:sm.sm_name.loc env members in
      let coverage =
        if config.coverage then Check_warn.signal_coverage ~sm_name env members
        else []
      in
      let live =
        if config.liveness then Check_warn.liveness ~sm_name members else []
      in
      let unused =
        if config.unused then
          Check_warn.unused_declarations ~sm_name env members
        else []
      in
      let shadow =
        if config.shadowing then
          Check_warn.transition_shadowing ~sm_name members
        else []
      in
      let dead =
        if config.deadlock then Check_warn.deadlock_states ~sm_name env members
        else []
      in
      core @ coverage @ live @ unused @ shadow @ dead

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

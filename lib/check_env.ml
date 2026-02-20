(** Shared types and utilities for state machine checks. *)

module SMap = Map.Make (String)
module SSet = Set.Make (String)

type diagnostic = {
  severity : [ `Error | `Warning ];
  loc : Ast.loc;
  sm_name : string;
  msg : string;
}

let pp_diagnostic ppf d =
  let sev = match d.severity with `Error -> "error" | `Warning -> "warning" in
  Fmt.pf ppf "%s:%d:%d: %s in SM '%s': %s" d.loc.file d.loc.line d.loc.col sev
    d.sm_name d.msg

let error ~sm_name loc msg = { severity = `Error; loc; sm_name; msg }
let errorf ~sm_name loc fmt = Fmt.kstr (error ~sm_name loc) fmt
let warning ~sm_name loc msg = { severity = `Warning; loc; sm_name; msg }
let warningf ~sm_name loc fmt = Fmt.kstr (warning ~sm_name loc) fmt

(* ── Severity levels ────────────────────────────────────────────────── *)

type level = Off | Warning | Error

let run_analysis level f =
  match level with
  | Off -> []
  | Warning -> f ()
  | Error ->
      f () |> List.map (fun (d : diagnostic) -> { d with severity = `Error })

(* ── Environment ────────────────────────────────────────────────────── *)

type env = {
  actions : Ast.loc SMap.t;
  guards : Ast.loc SMap.t;
  signals : Ast.loc SMap.t;
  states : Ast.loc SMap.t;
  choices : Ast.loc SMap.t;
  types : Ast.loc SMap.t;
  constants : Ast.loc SMap.t;
  action_types : Ast.type_name Ast.node option SMap.t;
  guard_types : Ast.type_name Ast.node option SMap.t;
  signal_types : Ast.type_name Ast.node option SMap.t;
  type_aliases : Ast.type_name Ast.node SMap.t;
}

let empty_env =
  {
    actions = SMap.empty;
    guards = SMap.empty;
    signals = SMap.empty;
    states = SMap.empty;
    choices = SMap.empty;
    types = SMap.empty;
    constants = SMap.empty;
    action_types = SMap.empty;
    guard_types = SMap.empty;
    signal_types = SMap.empty;
    type_aliases = SMap.empty;
  }

let add_enum_constants env (e : Ast.def_enum) =
  List.fold_left
    (fun m ann ->
      let (c : Ast.def_enum_constant) = (Ast.unannotate ann).Ast.data in
      SMap.add c.enum_const_name.data c.enum_const_name.loc m)
    env.constants e.enum_constants

let env_add_sm_member env = function
  | Ast.Sm_def_action a ->
      {
        env with
        actions = SMap.add a.action_name.data a.action_name.loc env.actions;
        action_types =
          SMap.add a.action_name.data a.action_type env.action_types;
      }
  | Ast.Sm_def_guard g ->
      {
        env with
        guards = SMap.add g.guard_name.data g.guard_name.loc env.guards;
        guard_types = SMap.add g.guard_name.data g.guard_type env.guard_types;
      }
  | Ast.Sm_def_signal s ->
      {
        env with
        signals = SMap.add s.signal_name.data s.signal_name.loc env.signals;
        signal_types =
          SMap.add s.signal_name.data s.signal_type env.signal_types;
      }
  | Ast.Sm_def_state s ->
      {
        env with
        states = SMap.add s.state_name.data s.state_name.loc env.states;
      }
  | Ast.Sm_def_choice c ->
      {
        env with
        choices = SMap.add c.choice_name.data c.choice_name.loc env.choices;
      }
  | Ast.Sm_def_constant c ->
      {
        env with
        constants = SMap.add c.const_name.data c.const_name.loc env.constants;
      }
  | Ast.Sm_def_abs_type t ->
      { env with types = SMap.add t.abs_name.data t.abs_name.loc env.types }
  | Ast.Sm_def_alias_type t ->
      {
        env with
        types = SMap.add t.alias_name.data t.alias_name.loc env.types;
        type_aliases = SMap.add t.alias_name.data t.alias_type env.type_aliases;
      }
  | Ast.Sm_def_array a ->
      { env with types = SMap.add a.array_name.data a.array_name.loc env.types }
  | Ast.Sm_def_enum e ->
      {
        env with
        types = SMap.add e.enum_name.data e.enum_name.loc env.types;
        constants = add_enum_constants env e;
      }
  | Ast.Sm_def_struct s ->
      {
        env with
        types = SMap.add s.struct_name.data s.struct_name.loc env.types;
      }
  | _ -> env

let build_sm_env members =
  List.fold_left
    (fun env ann -> env_add_sm_member env (Ast.unannotate ann).Ast.data)
    empty_env members

let build_state_env (st : Ast.def_state) parent_env =
  List.fold_left
    (fun env ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state s ->
          {
            env with
            states = SMap.add s.state_name.data s.state_name.loc env.states;
          }
      | Ast.State_def_choice c ->
          {
            env with
            choices = SMap.add c.choice_name.data c.choice_name.loc env.choices;
          }
      | _ -> env)
    parent_env st.state_members

(* ── Target helpers ─────────────────────────────────────────────────── *)

let target_name (qi : Ast.qual_ident Ast.node) =
  match qi.data with
  | Ast.Unqualified id -> id.data
  | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data

let is_qualified_target (qi : Ast.qual_ident Ast.node) =
  match qi.data with Ast.Qualified _ -> true | Ast.Unqualified _ -> false

(** Build a map from choice name to its def (for chain following). *)
let build_choice_map members =
  let m = Hashtbl.create 16 in
  let rec from_sm ms =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_def_choice c -> Hashtbl.replace m c.choice_name.data c
        | Ast.Sm_def_state st -> from_state st
        | _ -> ())
      ms
  and from_state (st : Ast.def_state) =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_choice c -> Hashtbl.replace m c.choice_name.data c
        | Ast.State_def_state sub -> from_state sub
        | _ -> ())
      st.state_members
  in
  from_sm members;
  m

(* ── State introspection ────────────────────────────────────────────── *)

let state_direct_signals (st : Ast.def_state) =
  List.fold_left
    (fun acc ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> SSet.add tr.st_signal.data acc
      | _ -> acc)
    SSet.empty st.state_members

let state_has_substates (st : Ast.def_state) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state _ -> true
      | _ -> false)
    st.state_members

let collect_substates (st : Ast.def_state) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state sub -> Some sub
      | _ -> None)
    st.state_members

let collect_sm_states members =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_state st -> Some st
      | _ -> None)
    members

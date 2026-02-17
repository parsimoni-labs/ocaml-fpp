(** State machine static analysis. *)

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

(* --- 1. Name redefinition detection --- *)

module SMap = Map.Make (String)

type name_kind = Action | Guard | Signal | State | Choice | Constant

let string_of_kind = function
  | Action -> "action"
  | Guard -> "guard"
  | Signal -> "signal"
  | State -> "state"
  | Choice -> "choice"
  | Constant -> "constant"

let duplicate_names ~sm_name members =
  let seen = Hashtbl.create 16 in
  let diags = ref [] in
  let add kind (id : Ast.ident Ast.node) =
    let key = (string_of_kind kind, id.data) in
    match Hashtbl.find_opt seen key with
    | Some prev_loc ->
        diags :=
          error ~sm_name id.loc
            (Fmt.str "duplicate %s '%s' (first defined at %s:%d:%d)"
               (string_of_kind kind) id.data prev_loc.Ast.file prev_loc.line
               prev_loc.col)
          :: !diags
    | None -> Hashtbl.replace seen key id.loc
  in
  List.iter
    (fun ann ->
      match Ast.unannotate ann with
      | { Ast.data = Ast.Sm_def_action a; _ } -> add Action a.action_name
      | { data = Ast.Sm_def_guard g; _ } -> add Guard g.guard_name
      | { data = Ast.Sm_def_signal s; _ } -> add Signal s.signal_name
      | { data = Ast.Sm_def_state s; _ } -> add State s.state_name
      | { data = Ast.Sm_def_choice c; _ } -> add Choice c.choice_name
      | { data = Ast.Sm_def_constant c; _ } -> add Constant c.const_name
      | _ -> ())
    members;
  List.rev !diags

let rec state_duplicate_names ~sm_name (st : Ast.def_state) =
  let seen = Hashtbl.create 8 in
  let diags = ref [] in
  let add kind (id : Ast.ident Ast.node) =
    let key = (string_of_kind kind, id.data) in
    match Hashtbl.find_opt seen key with
    | Some prev_loc ->
        diags :=
          error ~sm_name id.loc
            (Fmt.str "duplicate %s '%s' (first defined at %s:%d:%d)"
               (string_of_kind kind) id.data prev_loc.Ast.file prev_loc.line
               prev_loc.col)
          :: !diags
    | None -> Hashtbl.replace seen key id.loc
  in
  List.iter
    (fun ann ->
      match Ast.unannotate ann with
      | { Ast.data = Ast.State_def_state s; _ } -> add State s.state_name
      | { data = Ast.State_def_choice c; _ } -> add Choice c.choice_name
      | _ -> ())
    st.state_members;
  let nested =
    List.concat_map
      (fun ann ->
        match Ast.unannotate ann with
        | { Ast.data = Ast.State_def_state s; _ } ->
            state_duplicate_names ~sm_name s
        | _ -> [])
      st.state_members
  in
  List.rev !diags @ nested

(* --- 2. Initial transition validation --- *)

let validate_sm_initial ~sm_name members =
  let initials =
    List.filter_map
      (fun ann ->
        match Ast.unannotate ann with
        | { Ast.data = Ast.Sm_initial _; loc; _ } -> Some loc
        | _ -> None)
      members
  in
  let has_members =
    List.exists
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_def_state _ | Ast.Sm_def_choice _ -> true
        | _ -> false)
      members
  in
  let diags = ref [] in
  (match initials with
  | [] ->
      if has_members then
        let loc =
          match members with
          | ann :: _ -> (Ast.unannotate ann).Ast.loc
          | [] -> Ast.dummy_loc
        in
        diags :=
          error ~sm_name loc "state machine has no initial transition" :: !diags
  | [ _ ] -> ()
  | _ :: rest ->
      List.iter
        (fun loc ->
          diags :=
            error ~sm_name loc "state machine has multiple initial transitions"
            :: !diags)
        rest);
  List.rev !diags

let rec validate_state_initial ~sm_name (st : Ast.def_state) =
  let has_substates =
    List.exists
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_state _ -> true
        | _ -> false)
      st.state_members
  in
  let initials =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_initial _ -> Some (Ast.unannotate ann).Ast.loc
        | _ -> None)
      st.state_members
  in
  let diags = ref [] in
  (if has_substates then
     match initials with
     | [] ->
         diags :=
           error ~sm_name st.state_name.loc
             (Fmt.str "state '%s' has substates but no initial transition"
                st.state_name.data)
           :: !diags
     | [ _ ] -> ()
     | _ :: rest ->
         List.iter
           (fun loc ->
             diags :=
               error ~sm_name loc
                 (Fmt.str "state '%s' has multiple initial transitions"
                    st.state_name.data)
               :: !diags)
           rest);
  let nested =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_state s -> validate_state_initial ~sm_name s
        | _ -> [])
      st.state_members
  in
  List.rev !diags @ nested

(* --- 3. Undefined reference detection --- *)

type env = {
  actions : Ast.loc SMap.t;
  guards : Ast.loc SMap.t;
  signals : Ast.loc SMap.t;
  states : Ast.loc SMap.t;
  choices : Ast.loc SMap.t;
}

let empty_env =
  {
    actions = SMap.empty;
    guards = SMap.empty;
    signals = SMap.empty;
    states = SMap.empty;
    choices = SMap.empty;
  }

let build_sm_env members =
  List.fold_left
    (fun env ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_action a ->
          {
            env with
            actions = SMap.add a.action_name.data a.action_name.loc env.actions;
          }
      | Ast.Sm_def_guard g ->
          {
            env with
            guards = SMap.add g.guard_name.data g.guard_name.loc env.guards;
          }
      | Ast.Sm_def_signal s ->
          {
            env with
            signals = SMap.add s.signal_name.data s.signal_name.loc env.signals;
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
      | _ -> env)
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

let resolve_target env (qi : Ast.qual_ident Ast.node) =
  let name =
    match qi.data with
    | Ast.Unqualified id -> id.data
    | Ast.Qualified (q, _) -> (
        match q.data with
        | Ast.Unqualified id -> id.data
        | Ast.Qualified _ ->
            let ids = Ast.qual_ident_to_list qi.data in
            (List.hd ids).data)
  in
  SMap.mem name env.states || SMap.mem name env.choices

let verify_target ~sm_name env (qi : Ast.qual_ident Ast.node) =
  if resolve_target env qi then []
  else
    let name = Ast.qual_ident_to_string qi.data in
    [ error ~sm_name qi.loc (Fmt.str "undefined state or choice '%s'" name) ]

let verify_action ~sm_name env (id : Ast.ident Ast.node) =
  if SMap.mem id.data env.actions then []
  else [ error ~sm_name id.loc (Fmt.str "undefined action '%s'" id.data) ]

let verify_guard ~sm_name env (id : Ast.ident Ast.node) =
  if SMap.mem id.data env.guards then []
  else [ error ~sm_name id.loc (Fmt.str "undefined guard '%s'" id.data) ]

let verify_signal ~sm_name env (id : Ast.ident Ast.node) =
  if SMap.mem id.data env.signals then []
  else [ error ~sm_name id.loc (Fmt.str "undefined signal '%s'" id.data) ]

let verify_trans_expr ~sm_name env (te : Ast.transition_expr) =
  List.concat_map (verify_action ~sm_name env) te.trans_actions
  @ verify_target ~sm_name env te.trans_target

let verify_choice_members ~sm_name env (c : Ast.def_choice) =
  List.concat_map
    (fun cm ->
      match cm with
      | Ast.Choice_if (guard_opt, te) ->
          (match guard_opt with
            | Some g -> verify_guard ~sm_name env g
            | None -> [])
          @ verify_trans_expr ~sm_name env te.data
      | Ast.Choice_else te -> verify_trans_expr ~sm_name env te.data)
    c.choice_members

let verify_transition_or_do ~sm_name env = function
  | Ast.Transition te -> verify_trans_expr ~sm_name env te.data
  | Ast.Do actions -> List.concat_map (verify_action ~sm_name env) actions

let rec sm_undef_refs ~sm_name env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_initial te -> verify_trans_expr ~sm_name env te.data
      | Ast.Sm_def_choice c -> verify_choice_members ~sm_name env c
      | Ast.Sm_def_state st -> state_undef_refs ~sm_name env st
      | _ -> [])
    members

and state_undef_refs ~sm_name parent_env (st : Ast.def_state) =
  let env = build_state_env st parent_env in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_initial te -> verify_trans_expr ~sm_name env te.data
      | Ast.State_transition tr ->
          verify_signal ~sm_name env tr.st_signal
          @ (match tr.st_guard with
            | Some g -> verify_guard ~sm_name env g
            | None -> [])
          @ verify_transition_or_do ~sm_name env tr.st_action
      | Ast.State_entry actions ->
          List.concat_map (verify_action ~sm_name env) actions
      | Ast.State_exit actions ->
          List.concat_map (verify_action ~sm_name env) actions
      | Ast.State_def_choice c -> verify_choice_members ~sm_name env c
      | Ast.State_def_state sub -> state_undef_refs ~sm_name env sub
      | _ -> [])
    st.state_members

(* --- 4. Duplicate signal transitions --- *)

let dup_signal_trans ~sm_name (st : Ast.def_state) =
  let seen = Hashtbl.create 8 in
  let diags = ref [] in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> (
          let sig_name = tr.st_signal.data in
          match Hashtbl.find_opt seen sig_name with
          | Some prev_loc ->
              diags :=
                error ~sm_name tr.st_signal.loc
                  (Fmt.str
                     "duplicate transition on signal '%s' in state '%s' (first \
                      at %s:%d:%d)"
                     sig_name st.state_name.data prev_loc.Ast.file prev_loc.line
                     prev_loc.col)
                :: !diags
          | None -> Hashtbl.replace seen sig_name tr.st_signal.loc)
      | _ -> ())
    st.state_members;
  List.rev !diags

let rec collect_dup_signals ~sm_name members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_state st ->
          dup_signal_trans ~sm_name st @ collect_dup_signals_nested ~sm_name st
      | _ -> [])
    members

and collect_dup_signals_nested ~sm_name (st : Ast.def_state) =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state sub ->
          dup_signal_trans ~sm_name sub
          @ collect_dup_signals_nested ~sm_name sub
      | _ -> [])
    st.state_members

(* --- 5. Reachability analysis --- *)

let collect_all_targets members =
  let states = Hashtbl.create 16 in
  let choices = Hashtbl.create 16 in
  let rec from_sm_members ms =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_def_state s ->
            Hashtbl.replace states s.state_name.data s.state_name.loc;
            from_state_members s
        | Ast.Sm_def_choice c ->
            Hashtbl.replace choices c.choice_name.data c.choice_name.loc
        | _ -> ())
      ms
  and from_state_members (st : Ast.def_state) =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_state s ->
            Hashtbl.replace states s.state_name.data s.state_name.loc;
            from_state_members s
        | Ast.State_def_choice c ->
            Hashtbl.replace choices c.choice_name.data c.choice_name.loc
        | _ -> ())
      st.state_members
  in
  from_sm_members members;
  (states, choices)

let collect_reachable_targets members =
  let visited = Hashtbl.create 16 in
  let add_target (qi : Ast.qual_ident Ast.node) =
    let name =
      match qi.data with
      | Ast.Unqualified id -> id.data
      | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data
    in
    Hashtbl.replace visited name true
  in
  let visit_trans_expr (te : Ast.transition_expr) =
    add_target te.trans_target
  in
  let visit_choice (c : Ast.def_choice) =
    List.iter
      (function
        | Ast.Choice_if (_, te) -> visit_trans_expr te.data
        | Ast.Choice_else te -> visit_trans_expr te.data)
      c.choice_members
  in
  let rec visit_sm_members ms =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_initial te -> visit_trans_expr te.data
        | Ast.Sm_def_choice c -> visit_choice c
        | Ast.Sm_def_state st -> visit_state st
        | _ -> ())
      ms
  and visit_state (st : Ast.def_state) =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_initial te -> visit_trans_expr te.data
        | Ast.State_transition tr -> (
            match tr.st_action with
            | Ast.Transition te -> visit_trans_expr te.data
            | Ast.Do _ -> ())
        | Ast.State_def_choice c -> visit_choice c
        | Ast.State_def_state sub -> visit_state sub
        | _ -> ())
      st.state_members
  in
  visit_sm_members members;
  visited

let unreachable ~sm_name members =
  let all_states, all_choices = collect_all_targets members in
  let reachable = collect_reachable_targets members in
  let diags = ref [] in
  Hashtbl.iter
    (fun name loc ->
      if not (Hashtbl.mem reachable name) then
        diags :=
          error ~sm_name loc (Fmt.str "unreachable state '%s'" name) :: !diags)
    all_states;
  Hashtbl.iter
    (fun name loc ->
      if not (Hashtbl.mem reachable name) then
        diags :=
          error ~sm_name loc (Fmt.str "unreachable choice '%s'" name) :: !diags)
    all_choices;
  !diags

(* --- 6. Choice cycle detection --- *)

let build_choice_graph members =
  let graph = Hashtbl.create 16 in
  let all_choices = Hashtbl.create 16 in
  let add_edge from_name to_name =
    let edges =
      match Hashtbl.find_opt graph from_name with Some es -> es | None -> []
    in
    Hashtbl.replace graph from_name (to_name :: edges)
  in
  let target_name (qi : Ast.qual_ident Ast.node) =
    match qi.data with
    | Ast.Unqualified id -> id.data
    | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data
  in
  let visit_choice (c : Ast.def_choice) =
    Hashtbl.replace all_choices c.choice_name.data c.choice_name.loc;
    List.iter
      (fun cm ->
        let te =
          match cm with Ast.Choice_if (_, te) -> te | Ast.Choice_else te -> te
        in
        let t = target_name te.data.trans_target in
        add_edge c.choice_name.data t)
      c.choice_members
  in
  let rec from_sm_members ms =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_def_choice c -> visit_choice c
        | Ast.Sm_def_state st -> from_state st
        | _ -> ())
      ms
  and from_state (st : Ast.def_state) =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_choice c -> visit_choice c
        | Ast.State_def_state sub -> from_state sub
        | _ -> ())
      st.state_members
  in
  from_sm_members members;
  (graph, all_choices)

let choice_cycles ~sm_name members =
  let graph, all_choices = build_choice_graph members in
  let visited = Hashtbl.create 16 in
  let in_stack = Hashtbl.create 16 in
  let diags = ref [] in
  let rec dfs node =
    if Hashtbl.mem in_stack node then
      let loc =
        match Hashtbl.find_opt all_choices node with
        | Some l -> l
        | None -> Ast.dummy_loc
      in
      diags :=
        error ~sm_name loc (Fmt.str "choice '%s' is part of a cycle" node)
        :: !diags
    else if not (Hashtbl.mem visited node) then (
      Hashtbl.replace visited node true;
      Hashtbl.replace in_stack node true;
      (match Hashtbl.find_opt graph node with
      | Some edges ->
          List.iter
            (fun target -> if Hashtbl.mem all_choices target then dfs target)
            edges
      | None -> ());
      Hashtbl.remove in_stack node)
  in
  Hashtbl.iter (fun name _ -> dfs name) all_choices;
  !diags

(* --- Main entry points --- *)

let state_machine (sm : Ast.def_state_machine) =
  let sm_name = sm.sm_name.data in
  match sm.sm_members with
  | None -> []
  | Some members ->
      let dup_names = duplicate_names ~sm_name members in
      let state_dup_names =
        List.concat_map
          (fun ann ->
            match (Ast.unannotate ann).Ast.data with
            | Ast.Sm_def_state st -> state_duplicate_names ~sm_name st
            | _ -> [])
          members
      in
      let initial = validate_sm_initial ~sm_name members in
      let state_initial =
        List.concat_map
          (fun ann ->
            match (Ast.unannotate ann).Ast.data with
            | Ast.Sm_def_state st -> validate_state_initial ~sm_name st
            | _ -> [])
          members
      in
      let env = build_sm_env members in
      let undef = sm_undef_refs ~sm_name env members in
      let dup_signals = collect_dup_signals ~sm_name members in
      let reachability = unreachable ~sm_name members in
      let cycles = choice_cycles ~sm_name members in
      dup_names @ state_dup_names @ initial @ state_initial @ undef
      @ dup_signals @ reachability @ cycles

let rec collect_state_machines members =
  List.concat_map
    (fun (_, n, _) ->
      match n.Ast.data with
      | Ast.Mod_def_state_machine sm -> [ sm ]
      | Ast.Mod_def_module m -> collect_state_machines m.Ast.module_members
      | _ -> [])
    members

let run tu =
  let sms = collect_state_machines tu.Ast.tu_members in
  List.concat_map state_machine sms

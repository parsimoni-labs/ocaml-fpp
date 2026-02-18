(** Warning-level analyses for state machines.

    These optional checks detect suspicious patterns that may indicate bugs but
    are not necessarily errors: missing signal handlers, livelock cycles, unused
    declarations, transition shadowing, and potential deadlocks. Each analysis
    can be individually disabled via {!Check.skip}. *)

open Check_env

(* ── Signal coverage ────────────────────────────────────────────────── *)

let missing_signal_warnings ~sm_name all_signals covered (st : Ast.def_state) =
  let missing = SSet.diff all_signals covered in
  SSet.elements missing
  |> List.map (fun sig_name ->
      warning ~sm_name st.state_name.loc
        (Fmt.str "signal '%s' not handled in state '%s'" sig_name
           st.state_name.data))

let signal_coverage ~sm_name env members =
  let all_signals =
    SMap.fold (fun name _ acc -> SSet.add name acc) env.signals SSet.empty
  in
  if SSet.is_empty all_signals then []
  else
    let rec walk_state ~inherited (st : Ast.def_state) =
      let covered = SSet.union inherited (state_direct_signals st) in
      if state_has_substates st then
        List.concat_map (walk_state ~inherited:covered) (collect_substates st)
      else missing_signal_warnings ~sm_name all_signals covered st
    in
    List.concat_map
      (walk_state ~inherited:SSet.empty)
      (collect_sm_states members)

(* ── Liveness analysis ──────────────────────────────────────────────── *)

(** Resolve a choice target through chains, returning the set of terminal
    (non-choice) state names reachable. *)
let rec resolve_choice choice_map visited name =
  if SSet.mem name visited then SSet.empty
  else
    let visited = SSet.add name visited in
    match Hashtbl.find_opt choice_map name with
    | None -> SSet.singleton name
    | Some (c : Ast.def_choice) ->
        List.fold_left
          (fun acc cm ->
            let te =
              match cm with
              | Ast.Choice_if (_, te) -> te
              | Ast.Choice_else te -> te
            in
            SSet.union acc
              (resolve_choice choice_map visited
                 (target_name te.data.trans_target)))
          SSet.empty c.choice_members

(** Visit a leaf state: ensure it appears in the graph and record its
    signal-triggered transitions. *)
let visit_leaf_state choice_map graph name (st : Ast.def_state) =
  if not (SMap.mem name !graph) then graph := SMap.add name SSet.empty !graph;
  let add_edge to_st =
    let prev =
      match SMap.find_opt name !graph with Some s -> s | None -> SSet.empty
    in
    graph := SMap.add name (SSet.add to_st prev) !graph
  in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> (
          match tr.st_action with
          | Ast.Transition te ->
              let targets =
                resolve_choice choice_map SSet.empty
                  (target_name te.data.trans_target)
              in
              SSet.iter add_edge targets
          | Ast.Do _ -> ())
      | _ -> ())
    st.state_members

(** Visit a parent state: record initial transition edges and recurse into child
    states. *)
let visit_parent_state choice_map graph locs visit_state name
    (st : Ast.def_state) =
  let add_edge to_st =
    let prev =
      match SMap.find_opt name !graph with Some s -> s | None -> SSet.empty
    in
    graph := SMap.add name (SSet.add to_st prev) !graph
  in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_initial te ->
          let targets =
            resolve_choice choice_map SSet.empty
              (target_name te.data.trans_target)
          in
          SSet.iter add_edge targets
      | _ -> ())
    st.state_members;
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state sub ->
          visit_state choice_map graph locs ~prefix:name sub
      | _ -> ())
    st.state_members

(** Build a transition graph over flat state names. Returns: adjacency list
    (state -> set of successor states), plus a map of state name -> loc for
    diagnostics. *)
let build_state_graph members =
  let choice_map = build_choice_map members in
  let graph : SSet.t SMap.t ref = ref SMap.empty in
  let locs : Ast.loc SMap.t ref = ref SMap.empty in
  let rec visit_state choice_map graph locs ~prefix (st : Ast.def_state) =
    let name =
      match prefix with
      | "" -> st.state_name.data
      | p -> p ^ "." ^ st.state_name.data
    in
    locs := SMap.add name st.state_name.loc !locs;
    if state_has_substates st then
      visit_parent_state choice_map graph locs visit_state name st
    else visit_leaf_state choice_map graph name st
  in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_state st -> visit_state choice_map graph locs ~prefix:"" st
      | _ -> ())
    members;
  (!graph, !locs)

(** Pop nodes from [stack] until [root] is reached, returning the SCC set. *)
let pop_scc stack on_stack root =
  let scc = ref SSet.empty in
  let continue = ref true in
  while !continue do
    match !stack with
    | w :: rest ->
        stack := rest;
        Hashtbl.remove on_stack w;
        scc := SSet.add w !scc;
        if w = root then continue := false
    | [] -> continue := false
  done;
  !scc

(** Update [lowlinks] for [v] from successor [w]. *)
let update_lowlink lowlinks v w =
  let lw = Hashtbl.find lowlinks w in
  let lv = Hashtbl.find lowlinks v in
  if lw < lv then Hashtbl.replace lowlinks v lw

(** Process a single successor [w] of node [v] during Tarjan traversal. *)
let process_successor indices lowlinks on_stack strongconnect v w =
  if not (Hashtbl.mem indices w) then (
    strongconnect w;
    update_lowlink lowlinks v w)
  else if Hashtbl.mem on_stack w then
    let iw = Hashtbl.find indices w in
    let lv = Hashtbl.find lowlinks v in
    if iw < lv then Hashtbl.replace lowlinks v iw

(** Tarjan's SCC algorithm. Returns list of SCCs (each is a set of state names).
*)
let tarjan_scc graph =
  let index = ref 0 in
  let stack = ref [] in
  let on_stack = Hashtbl.create 16 in
  let indices = Hashtbl.create 16 in
  let lowlinks = Hashtbl.create 16 in
  let sccs = ref [] in
  let rec strongconnect v =
    Hashtbl.replace indices v !index;
    Hashtbl.replace lowlinks v !index;
    incr index;
    stack := v :: !stack;
    Hashtbl.replace on_stack v true;
    let succs =
      match SMap.find_opt v graph with Some s -> s | None -> SSet.empty
    in
    SSet.iter
      (process_successor indices lowlinks on_stack strongconnect v)
      succs;
    if Hashtbl.find lowlinks v = Hashtbl.find indices v then
      sccs := pop_scc stack on_stack v :: !sccs
  in
  SMap.iter
    (fun v _ -> if not (Hashtbl.mem indices v) then strongconnect v)
    graph;
  !sccs

(** Reverse a directed graph: for each edge [src -> dst], produce [dst -> src].
*)
let reverse_graph graph =
  SMap.fold
    (fun src succs acc ->
      SSet.fold
        (fun dst acc ->
          let prev =
            match SMap.find_opt dst acc with Some s -> s | None -> SSet.empty
          in
          SMap.add dst (SSet.add src prev) acc)
        succs acc)
    graph SMap.empty

(** Backward BFS from [seeds]: returns a hashtable of all nodes that can reach
    any seed via the [rev_graph]. *)
let backward_reachable rev_graph seeds =
  let visited = Hashtbl.create 16 in
  let queue = Queue.create () in
  SSet.iter
    (fun t ->
      Hashtbl.replace visited t true;
      Queue.push t queue)
    seeds;
  while not (Queue.is_empty queue) do
    let node = Queue.pop queue in
    let preds =
      match SMap.find_opt node rev_graph with Some s -> s | None -> SSet.empty
    in
    SSet.iter
      (fun p ->
        if not (Hashtbl.mem visited p) then (
          Hashtbl.replace visited p true;
          Queue.push p queue))
      preds
  done;
  visited

(** Check liveness: warn about states trapped in cycles with no exit to a
    terminal state. *)
let liveness ~sm_name members =
  let graph, locs = build_state_graph members in
  if SMap.cardinal graph <= 1 then []
  else
    let terminals =
      SMap.fold
        (fun name succs acc ->
          if SSet.is_empty succs then SSet.add name acc else acc)
        graph SSet.empty
    in
    let can_terminate = backward_reachable (reverse_graph graph) terminals in
    let sccs = tarjan_scc graph in
    List.concat_map
      (fun scc ->
        if SSet.cardinal scc < 2 then []
        else if SSet.exists (fun s -> Hashtbl.mem can_terminate s) scc then []
        else
          let states = SSet.elements scc in
          let repr = List.hd states in
          let loc =
            match SMap.find_opt repr locs with
            | Some l -> l
            | None -> Ast.dummy_loc
          in
          [
            warning ~sm_name loc
              (Fmt.str "states {%s} form a cycle with no exit"
                 (String.concat ", " (List.map (fun s -> "'" ^ s ^ "'") states)));
          ])
      sccs

(* ── Unused declarations ────────────────────────────────────────────── *)

(** Collect all action/guard/signal names actually referenced in transitions,
    choices, entry/exit actions, and initial transitions. *)
let collect_used_names members =
  let used_actions = Hashtbl.create 16 in
  let used_guards = Hashtbl.create 16 in
  let used_signals = Hashtbl.create 16 in
  let use_action (id : Ast.ident Ast.node) =
    Hashtbl.replace used_actions id.data true
  in
  let use_guard (id : Ast.ident Ast.node) =
    Hashtbl.replace used_guards id.data true
  in
  let use_signal (id : Ast.ident Ast.node) =
    Hashtbl.replace used_signals id.data true
  in
  let visit_trans_expr (te : Ast.transition_expr) =
    List.iter use_action te.trans_actions
  in
  let visit_choice (c : Ast.def_choice) =
    List.iter
      (fun cm ->
        match cm with
        | Ast.Choice_if (guard_opt, te) ->
            Option.iter use_guard guard_opt;
            visit_trans_expr te.data
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
            use_signal tr.st_signal;
            Option.iter use_guard tr.st_guard;
            match tr.st_action with
            | Ast.Transition te -> visit_trans_expr te.data
            | Ast.Do actions -> List.iter use_action actions)
        | Ast.State_entry actions -> List.iter use_action actions
        | Ast.State_exit actions -> List.iter use_action actions
        | Ast.State_def_choice c -> visit_choice c
        | Ast.State_def_state sub -> visit_state sub
        | _ -> ())
      st.state_members
  in
  visit_sm_members members;
  (used_actions, used_guards, used_signals)

let unused_declarations ~sm_name env members =
  let used_actions, used_guards, used_signals = collect_used_names members in
  let check_unused kind used declared =
    SMap.fold
      (fun name loc acc ->
        if Hashtbl.mem used name then acc
        else warning ~sm_name loc (Fmt.str "unused %s '%s'" kind name) :: acc)
      declared []
  in
  check_unused "action" used_actions env.actions
  @ check_unused "guard" used_guards env.guards
  @ check_unused "signal" used_signals env.signals

(* ── Transition shadowing ───────────────────────────────────────────── *)

(** Warn when a child state handles a signal that an ancestor already handles.
    The child's handler shadows the parent's -- this may be intentional
    (override) or accidental. *)
let transition_shadowing ~sm_name members =
  let rec walk_state ~parent_signals (st : Ast.def_state) =
    let my_signals = state_direct_signals st in
    let shadowed = SSet.inter my_signals parent_signals in
    let warnings =
      SSet.fold
        (fun sig_name acc ->
          warning ~sm_name st.state_name.loc
            (Fmt.str "state '%s' shadows parent handler for signal '%s'"
               st.state_name.data sig_name)
          :: acc)
        shadowed []
    in
    let combined = SSet.union parent_signals my_signals in
    let sub_warnings =
      List.concat_map
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.State_def_state sub -> walk_state ~parent_signals:combined sub
          | _ -> [])
        st.state_members
    in
    warnings @ sub_warnings
  in
  List.concat_map
    (walk_state ~parent_signals:SSet.empty)
    (collect_sm_states members)

(* ── Sink state / deadlock detection ────────────────────────────────── *)

(** Warn about leaf states that have no outgoing transitions (direct or
    inherited from ancestors) when the state machine has signals defined. A
    state with no transitions and no ancestor handlers can never react to any
    event -- it is a potential deadlock. *)
let deadlock_states ~sm_name env members =
  if SMap.is_empty env.signals then []
  else
    let state_has_transitions (st : Ast.def_state) =
      List.exists
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.State_transition _ -> true
          | _ -> false)
        st.state_members
    in
    let rec walk_state ~inherited_handler (st : Ast.def_state) =
      let has_handler = inherited_handler || state_has_transitions st in
      match (state_has_substates st, has_handler) with
      | true, _ ->
          List.concat_map
            (fun ann ->
              match (Ast.unannotate ann).Ast.data with
              | Ast.State_def_state sub ->
                  walk_state ~inherited_handler:has_handler sub
              | _ -> [])
            st.state_members
      | false, true -> []
      | false, false ->
          [
            warning ~sm_name st.state_name.loc
              (Fmt.str
                 "state '%s' has no outgoing transitions (potential deadlock)"
                 st.state_name.data);
          ]
    in
    List.concat_map
      (walk_state ~inherited_handler:false)
      (collect_sm_states members)

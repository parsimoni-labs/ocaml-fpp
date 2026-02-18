(** State machine to D2 rendering.

    Produces D2 diagrams from FPP state machine definitions. D2
    (https://d2lang.com) is a modern diagramming language with clean default
    styling and native support for hierarchical containers.

    Inside containers, nodes use short names (e.g. [C], not [S2.C]). Edges are
    emitted at the top level using fully qualified IDs (e.g. [S2.C -> S1]) so
    that ELK can lay out cross-container transitions. *)

(* ── Helpers ──────────────────────────────────────────────────────── *)

module SSet = Set.Make (String)

let node_id prefix name = match prefix with "" -> name | p -> p ^ "." ^ name

let raw_target (qi : Ast.qual_ident Ast.node) =
  match qi.data with
  | Ast.Unqualified id -> id.data
  | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data

let collect_ids members =
  let ids = ref SSet.empty in
  let rec from_state ~prefix (st : Ast.def_state) =
    let id = node_id prefix st.state_name.data in
    ids := SSet.add id !ids;
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_state sub -> from_state ~prefix:id sub
        | Ast.State_def_choice c ->
            ids := SSet.add (node_id id c.choice_name.data) !ids
        | _ -> ())
      st.state_members
  in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_state st -> from_state ~prefix:"" st
      | Ast.Sm_def_choice c -> ids := SSet.add c.choice_name.data !ids
      | _ -> ())
    members;
  !ids

let resolve_target ids ~prefix (qi : Ast.qual_ident Ast.node) =
  let raw = raw_target qi in
  let local = node_id prefix raw in
  if SSet.mem local ids then local else raw

(* ── Label formatting ──────────────────────────────────────────────── *)

let actions_of_transition (tr : Ast.spec_state_transition) =
  match tr.st_action with
  | Ast.Transition te ->
      List.map (fun (a : Ast.ident Ast.node) -> a.data) te.data.trans_actions
  | Ast.Do acts -> List.map (fun (a : Ast.ident Ast.node) -> a.data) acts

let actions_of_trans_expr (te : Ast.transition_expr) =
  List.map (fun (a : Ast.ident Ast.node) -> a.data) te.trans_actions

(* ── Edge accumulator ─────────────────────────────────────────────── *)

type edge = {
  src : string;
  dst : string;
  label : string;
  guard : string option;
  actions : string option;
}

let edges : edge list ref = ref []

let add_edge src dst ?(guard : string option) ?(actions : string option) label =
  edges := { src; dst; label; guard; actions } :: !edges

(* ── D2 preamble ──────────────────────────────────────────────────── *)

let pp_preamble ppf name =
  Fmt.pf ppf
    {|vars: {
  d2-config: {
    layout-engine: elk
  }
}
classes: {
  state: {
    style.border-radius: 8
    style.fill: "#e8f0fe"
    style.stroke: "#4285f4"
    style.font-color: "#1a1a2e"
  }
  choice: {
    shape: diamond
    style.fill: "#fff8e1"
    style.stroke: "#f9ab00"
    style.font-color: "#1a1a2e"
  }
}
|};
  Fmt.pf ppf "# %s@." name;
  Fmt.pf ppf "direction: down@."

(* ── D2 node emission ─────────────────────────────────────────────── *)

let indent ppf depth =
  for _ = 1 to depth do
    Fmt.pf ppf "  "
  done

(** Emit a choice node. Uses [short_name] inside the container block; edges use
    the fully qualified [node_id prefix name]. *)
let emit_choice_node ppf ids ~depth ~prefix (c : Ast.def_choice) =
  let id = node_id prefix c.choice_name.data in
  let short = c.choice_name.data in
  indent ppf depth;
  Fmt.pf ppf "%s: %s { class: choice }@." short short;
  List.iter
    (fun cm ->
      match cm with
      | Ast.Choice_if (guard_opt, te) ->
          let guard_str =
            match guard_opt with
            | Some (g : Ast.ident Ast.node) -> "[" ^ g.data ^ "]"
            | None -> "[true]"
          in
          let target = resolve_target ids ~prefix te.data.trans_target in
          let acts = actions_of_trans_expr te.data in
          let actions =
            if acts = [] then None else Some ("/ " ^ String.concat ", " acts)
          in
          add_edge id target ?actions ("\"" ^ guard_str ^ "\"")
      | Ast.Choice_else te ->
          let target = resolve_target ids ~prefix te.data.trans_target in
          let acts = actions_of_trans_expr te.data in
          let actions =
            if acts = [] then None else Some ("/ " ^ String.concat ", " acts)
          in
          add_edge id target ?actions "else")
    c.choice_members

let action_names members tag =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | m when tag m ->
          let acts =
            match m with
            | Ast.State_entry acts | Ast.State_exit acts ->
                List.map (fun (a : Ast.ident Ast.node) -> a.data) acts
            | _ -> []
          in
          Some acts
      | _ -> None)
    members
  |> List.concat

let state_annotations st =
  let entry =
    let acts =
      action_names st.Ast.state_members (function
        | Ast.State_entry _ -> true
        | _ -> false)
    in
    if acts = [] then [] else [ "entry / " ^ String.concat ", " acts ]
  in
  let exit_ =
    let acts =
      action_names st.Ast.state_members (function
        | Ast.State_exit _ -> true
        | _ -> false)
    in
    if acts = [] then [] else [ "exit / " ^ String.concat ", " acts ]
  in
  entry @ exit_

let rec emit_composite ppf ids ~depth ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  let short = st.state_name.data in
  indent ppf depth;
  Fmt.pf ppf "%s: %s {@." short short;
  indent ppf (depth + 1);
  Fmt.pf ppf "style.border-radius: 8@.";
  indent ppf (depth + 1);
  Fmt.pf ppf "style.fill: \"#f8f9fa\"@.";
  indent ppf (depth + 1);
  Fmt.pf ppf "style.stroke: \"#5f6368\"@.";
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state sub ->
          emit_state_node ppf ids ~depth:(depth + 1) ~prefix:id sub
      | Ast.State_def_choice c ->
          emit_choice_node ppf ids ~depth:(depth + 1) ~prefix:id c
      | _ -> ())
    st.state_members;
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_initial te ->
          let target = resolve_target ids ~prefix:id te.data.trans_target in
          let acts = actions_of_trans_expr te.data in
          let actions =
            if acts = [] then None else Some ("/ " ^ String.concat ", " acts)
          in
          let init_id = id ^ ".__init__" in
          indent ppf (depth + 1);
          Fmt.pf ppf
            "__init__: \"\" { shape: circle; width: 12; height: 12; \
             style.fill: \"#1a1a2e\"; style.stroke: \"#1a1a2e\" }@.";
          add_edge init_id target ?actions ""
      | _ -> ())
    st.state_members;
  indent ppf depth;
  Fmt.pf ppf "}@."

and emit_leaf ppf ~depth (st : Ast.def_state) =
  let short = st.state_name.data in
  let extras = state_annotations st in
  indent ppf depth;
  if extras = [] then Fmt.pf ppf "%s: %s { class: state }@." short short
  else
    Fmt.pf ppf "%s: |md\n  **%s**\n  ---\n  %s\n| { class: state }@." short
      short
      (String.concat "\n  " extras)

and emit_state_node ppf ids ~depth ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  if Check_env.state_has_substates st then
    emit_composite ppf ids ~depth ~prefix st
  else emit_leaf ppf ~depth st;
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> (
          let signal = tr.st_signal.data in
          let guard =
            match tr.st_guard with
            | Some g -> Some ("[" ^ g.data ^ "]")
            | None -> None
          in
          let acts = actions_of_transition tr in
          let actions =
            if acts = [] then None else Some ("/ " ^ String.concat ", " acts)
          in
          match tr.st_action with
          | Ast.Transition te ->
              let target = resolve_target ids ~prefix te.data.trans_target in
              add_edge id target ?guard ?actions signal
          | Ast.Do _ -> add_edge id id ?guard ?actions signal)
      | _ -> ())
    st.state_members

(* ── Public API ────────────────────────────────────────────────────── *)

let pp ppf (sm : Ast.def_state_machine) =
  match sm.sm_members with
  | None -> ()
  | Some members ->
      let name = sm.sm_name.data in
      let ids = collect_ids members in
      edges := [];
      pp_preamble ppf name;
      List.iter
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Sm_initial te ->
              let target = resolve_target ids ~prefix:"" te.data.trans_target in
              let acts = actions_of_trans_expr te.data in
              let actions =
                if acts = [] then None else Some ("/ " ^ String.concat ", " acts)
              in
              Fmt.pf ppf
                "__init__: \"\" { shape: circle; width: 20; height: 20; \
                 style.fill: \"#1a1a2e\"; style.stroke: \"#1a1a2e\" }@.";
              add_edge "__init__" target ?actions ""
          | Ast.Sm_def_state st ->
              emit_state_node ppf ids ~depth:0 ~prefix:"" st
          | Ast.Sm_def_choice c ->
              emit_choice_node ppf ids ~depth:0 ~prefix:"" c
          | _ -> ())
        members;
      (* All edges at top level with fully qualified IDs *)
      List.iter
        (fun e ->
          match (e.label, e.guard, e.actions) with
          | "", None, None -> Fmt.pf ppf "%s -> %s@." e.src e.dst
          | lbl, None, None -> Fmt.pf ppf "%s -> %s: %s@." e.src e.dst lbl
          | lbl, guard, actions ->
              if lbl = "" then Fmt.pf ppf "%s -> %s {" e.src e.dst
              else Fmt.pf ppf "%s -> %s: %s {" e.src e.dst lbl;
              (match guard with
              | Some g -> Fmt.pf ppf "@.  source-arrowhead.label: %s" g
              | None -> ());
              (match actions with
              | Some a -> Fmt.pf ppf "@.  target-arrowhead.label: %s" a
              | None -> ());
              Fmt.pf ppf "@.}@.")
        (List.rev !edges)

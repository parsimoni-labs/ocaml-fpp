(** State machine to Graphviz DOT rendering.

    Produces DOT digraphs from FPP state machine definitions. Hierarchical
    states become cluster subgraphs, choices become diamond nodes, and
    transitions become labelled edges. *)

module SSet = Set.Make (String)

(* ── Node ID helpers ───────────────────────────────────────────────── *)

let node_id prefix name = match prefix with "" -> name | p -> p ^ "_" ^ name

let init_id prefix =
  match prefix with "" -> "__init__" | p -> "__init_" ^ p ^ "__"

(** Extract the raw target name from a qualified identifier. *)
let raw_target (qi : Ast.qual_ident Ast.node) =
  match qi.data with
  | Ast.Unqualified id -> id.data
  | Ast.Qualified _ ->
      String.map
        (fun c -> if c = '.' then '_' else c)
        (Ast.qual_ident_to_string qi.data)

(* ── Collect all node IDs ──────────────────────────────────────────── *)

(** First pass: collect all DOT node IDs (states and choices) so that targets
    can be resolved against the correct scope. *)
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

(** Resolve a transition target: try local scope first (prefix_target), then
    global (target). For qualified names, translate dots to underscores. *)
let resolve_target ids ~prefix (qi : Ast.qual_ident Ast.node) =
  let raw = raw_target qi in
  let local = node_id prefix raw in
  if SSet.mem local ids then local else raw

(* ── Label formatting ──────────────────────────────────────────────── *)

let transition_label (tr : Ast.spec_state_transition) =
  let signal = tr.st_signal.data in
  let guard =
    match tr.st_guard with Some g -> " [" ^ g.data ^ "]" | None -> ""
  in
  let actions =
    match tr.st_action with
    | Ast.Transition te ->
        let acts =
          List.map
            (fun (a : Ast.ident Ast.node) -> a.data)
            te.data.trans_actions
        in
        if acts = [] then "" else " / " ^ String.concat ", " acts
    | Ast.Do acts ->
        let names = List.map (fun (a : Ast.ident Ast.node) -> a.data) acts in
        if names = [] then "" else " / " ^ String.concat ", " names
  in
  signal ^ guard ^ actions

let trans_expr_label (te : Ast.transition_expr) =
  let acts =
    List.map (fun (a : Ast.ident Ast.node) -> a.data) te.trans_actions
  in
  if acts = [] then "" else " / " ^ String.concat ", " acts

let state_label (st : Ast.def_state) =
  let name = st.state_name.data in
  let entry =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_entry acts ->
            let names =
              List.map (fun (a : Ast.ident Ast.node) -> a.data) acts
            in
            Some ("entry / " ^ String.concat ", " names)
        | _ -> None)
      st.state_members
  in
  let exit_ =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_exit acts ->
            let names =
              List.map (fun (a : Ast.ident Ast.node) -> a.data) acts
            in
            Some ("exit / " ^ String.concat ", " names)
        | _ -> None)
      st.state_members
  in
  let extras = entry @ exit_ in
  if extras = [] then name else name ^ "\\n" ^ String.concat "\\n" extras

(* ── DOT emission ──────────────────────────────────────────────────── *)

let indent ppf depth =
  for _ = 1 to depth do
    Fmt.pf ppf "  "
  done

let emit_choice ppf ids ~depth ~prefix (c : Ast.def_choice) =
  let id = node_id prefix c.choice_name.data in
  indent ppf depth;
  Fmt.pf ppf "%s [label=\"%s\" shape=diamond]@." id c.choice_name.data;
  List.iter
    (fun cm ->
      match cm with
      | Ast.Choice_if (guard_opt, te) ->
          let guard_label =
            match guard_opt with
            | Some g -> "[" ^ g.data ^ "]"
            | None -> "[true]"
          in
          let target = resolve_target ids ~prefix te.data.trans_target in
          let acts = trans_expr_label te.data in
          indent ppf depth;
          Fmt.pf ppf "%s -> %s [label=\"%s%s\"]@." id target guard_label acts
      | Ast.Choice_else te ->
          let target = resolve_target ids ~prefix te.data.trans_target in
          let acts = trans_expr_label te.data in
          indent ppf depth;
          Fmt.pf ppf "%s -> %s [label=\"else%s\"]@." id target acts)
    c.choice_members

let rec emit_state ppf ids ~depth ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  let has_substates = Check_env.state_has_substates st in
  if has_substates then (
    indent ppf depth;
    Fmt.pf ppf "subgraph cluster_%s {@." id;
    indent ppf (depth + 1);
    Fmt.pf ppf "label=\"%s\"@." st.state_name.data;
    indent ppf (depth + 1);
    Fmt.pf ppf "style=rounded@.";
    let iid = init_id id in
    indent ppf (depth + 1);
    Fmt.pf ppf "%s [shape=point width=0.2]@." iid;
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_state sub ->
            emit_state ppf ids ~depth:(depth + 1) ~prefix:id sub
        | Ast.State_def_choice c ->
            emit_choice ppf ids ~depth:(depth + 1) ~prefix:id c
        | Ast.State_initial te ->
            let target = resolve_target ids ~prefix:id te.data.trans_target in
            let acts = trans_expr_label te.data in
            indent ppf (depth + 1);
            Fmt.pf ppf "%s -> %s [style=dashed label=\"%s\"]@." iid target acts
        | _ -> ())
      st.state_members;
    indent ppf depth;
    Fmt.pf ppf "}@.")
  else (
    indent ppf depth;
    Fmt.pf ppf "%s [label=\"%s\" shape=Mrecord]@." id (state_label st));
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> (
          let label = transition_label tr in
          match tr.st_action with
          | Ast.Transition te ->
              let target = resolve_target ids ~prefix te.data.trans_target in
              indent ppf depth;
              Fmt.pf ppf "%s -> %s [label=\"%s\"]@." id target label
          | Ast.Do _ ->
              indent ppf depth;
              Fmt.pf ppf "%s -> %s [label=\"%s\"]@." id id label)
      | _ -> ())
    st.state_members

(* ── Public API ────────────────────────────────────────────────────── *)

let pp ppf (sm : Ast.def_state_machine) =
  match sm.sm_members with
  | None -> ()
  | Some members ->
      let name = sm.sm_name.data in
      let ids = collect_ids members in
      Fmt.pf ppf "digraph %s {@." name;
      Fmt.pf ppf "  rankdir=TB@.";
      Fmt.pf ppf "  fontname=\"Helvetica\"@.";
      Fmt.pf ppf "  node [fontname=\"Helvetica\" fontsize=11]@.";
      Fmt.pf ppf "  edge [fontname=\"Helvetica\" fontsize=10]@.";
      Fmt.pf ppf "  __init__ [shape=point width=0.25]@.";
      List.iter
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Sm_initial te ->
              let target = resolve_target ids ~prefix:"" te.data.trans_target in
              let acts = trans_expr_label te.data in
              Fmt.pf ppf "  __init__ -> %s [style=dashed label=\"%s\"]@." target
                acts
          | Ast.Sm_def_state st -> emit_state ppf ids ~depth:1 ~prefix:"" st
          | Ast.Sm_def_choice c -> emit_choice ppf ids ~depth:1 ~prefix:"" c
          | _ -> ())
        members;
      Fmt.pf ppf "}@."

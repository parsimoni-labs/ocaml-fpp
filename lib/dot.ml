(** State machine to Graphviz DOT rendering.

    Produces DOT digraphs from FPP state machine definitions. Graphviz DOT gives
    first-class edge labels, self-loop support, [subgraph cluster_*] containers,
    and HTML table labels for structured state annotations.

    Node IDs are quoted to preserve dot-separated paths (e.g. ["P.A"]). Edges
    are collected during node emission and emitted at the top level. *)

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

(* ── DOT string escaping ─────────────────────────────────────────── *)

let escape_dot s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf {|\"|}
      | '\\' -> Buffer.add_string buf {|\\|}
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

(* ── Label formatting ─────────────────────────────────────────────── *)

let actions_of_transition (tr : Ast.spec_state_transition) =
  match tr.st_action with
  | Ast.Transition te ->
      List.map (fun (a : Ast.ident Ast.node) -> a.data) te.data.trans_actions
  | Ast.Do acts -> List.map (fun (a : Ast.ident Ast.node) -> a.data) acts

let actions_of_trans_expr (te : Ast.transition_expr) =
  List.map (fun (a : Ast.ident Ast.node) -> a.data) te.trans_actions

(** Build a unified edge label string. Components are omitted when empty. Lines
    are separated by [\\n] for DOT label rendering. *)
let edge_label signal guard actions =
  let first_line =
    match (signal, guard) with
    | "", None -> ""
    | "", Some g -> "[" ^ g ^ "]"
    | s, None -> s
    | s, Some g -> s ^ " [" ^ g ^ "]"
  in
  let action_line =
    match actions with
    | [] -> None
    | acts -> Some ("/ " ^ String.concat ", " acts)
  in
  match (first_line, action_line) with
  | "", None -> ""
  | "", Some a -> a
  | fl, None -> fl
  | fl, Some a -> fl ^ "\\n" ^ a

(* ── Edge accumulator ─────────────────────────────────────────────── *)

type edge = { src : string; dst : string; label : string }

let edges : edge list ref = ref []
let add_edge src dst label = edges := { src; dst; label } :: !edges

(* ── DOT indentation ──────────────────────────────────────────────── *)

let indent ppf depth =
  for _ = 1 to depth do
    Fmt.pf ppf "  "
  done

(* ── Preamble ─────────────────────────────────────────────────────── *)

let pp_preamble ppf name =
  Fmt.pf ppf {|digraph "%s" {@.|} (escape_dot name);
  Fmt.pf ppf
    {|  compound=true;
  rankdir=TB;
  bgcolor=white;
  pad="0.4";
  node [fontname="Helvetica" fontsize=11];
  edge [fontname="Helvetica" fontsize=9 color="#5f6368"];
|}

(* ── Node emission ────────────────────────────────────────────────── *)

let emit_initial ppf ~ind id =
  indent ppf ind;
  Fmt.pf ppf
    {|"%s" [shape=circle width=0.25 fixedsize=true style=filled fillcolor="#1a1a2e" label=""];@.|}
    (escape_dot id)

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

(** Build an HTML table label for a state with entry/exit actions. *)
let html_state_label name extras =
  let buf = Buffer.create 128 in
  Buffer.add_string buf {|<<table border="0" cellborder="0" cellspacing="0">|};
  Buffer.add_string buf
    (Fmt.str {|<tr><td><b>%s</b></td></tr>|} (escape_dot name));
  Buffer.add_string buf {|<HR/>|};
  List.iter
    (fun line ->
      Buffer.add_string buf
        (Fmt.str
           {|<tr><td align="left"><font point-size="9">%s</font></td></tr>|}
           (escape_dot line)))
    extras;
  Buffer.add_string buf {|</table>>|};
  Buffer.contents buf

let emit_leaf ppf ~ind ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  let extras = state_annotations st in
  indent ppf ind;
  if extras = [] then
    Fmt.pf ppf
      {|"%s" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label="%s"];@.|}
      (escape_dot id)
      (escape_dot st.state_name.data)
  else
    let label = html_state_label st.state_name.data extras in
    Fmt.pf ppf
      {|"%s" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" label=%s];@.|}
      (escape_dot id) label

(* ── Choice nodes ─────────────────────────────────────────────────── *)

let emit_choice_node ppf ids ~ind ~prefix (c : Ast.def_choice) =
  let id = node_id prefix c.choice_name.data in
  indent ppf ind;
  Fmt.pf ppf
    {|"%s" [shape=diamond style=filled fillcolor="#fff8e1" color="#f9ab00" label="%s"];@.|}
    (escape_dot id)
    (escape_dot c.choice_name.data);
  List.iter
    (fun cm ->
      match cm with
      | Ast.Choice_if (guard_opt, te) ->
          let guard_str =
            match guard_opt with
            | Some (g : Ast.ident Ast.node) -> Some g.data
            | None -> Some "true"
          in
          let target = resolve_target ids ~prefix te.data.trans_target in
          let acts = actions_of_trans_expr te.data in
          add_edge id target (edge_label "" guard_str acts)
      | Ast.Choice_else te ->
          let target = resolve_target ids ~prefix te.data.trans_target in
          let acts = actions_of_trans_expr te.data in
          add_edge id target (edge_label "else" None acts))
    c.choice_members

(* ── State nodes ──────────────────────────────────────────────────── *)

let rec emit_composite ppf ids ~depth ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  indent ppf depth;
  Fmt.pf ppf {|subgraph "cluster_%s" {@.|} (escape_dot id);
  indent ppf (depth + 1);
  Fmt.pf ppf {|label="%s";@.|} (escape_dot st.state_name.data);
  indent ppf (depth + 1);
  Fmt.pf ppf {|style="rounded,filled";@.|};
  indent ppf (depth + 1);
  Fmt.pf ppf {|fillcolor="#f8f9fa";@.|};
  indent ppf (depth + 1);
  Fmt.pf ppf {|color="#5f6368";@.|};
  indent ppf (depth + 1);
  Fmt.pf ppf {|fontname="Helvetica";@.|};
  (* Child nodes *)
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state sub ->
          emit_state_node ppf ids ~depth:(depth + 1) ~prefix:id sub
      | Ast.State_def_choice c ->
          emit_choice_node ppf ids ~ind:(depth + 1) ~prefix:id c
      | _ -> ())
    st.state_members;
  (* Initial transition inside composite *)
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_initial te ->
          let target = resolve_target ids ~prefix:id te.data.trans_target in
          let acts = actions_of_trans_expr te.data in
          let init_id = id ^ ".__init__" in
          emit_initial ppf ~ind:(depth + 1) init_id;
          add_edge init_id target (edge_label "" None acts)
      | _ -> ())
    st.state_members;
  indent ppf depth;
  Fmt.pf ppf "}@."

and emit_state_node ppf ids ~depth ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  if Check_env.state_has_substates st then
    emit_composite ppf ids ~depth ~prefix st
  else emit_leaf ppf ~ind:depth ~prefix st;
  (* Transitions from this state *)
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> (
          let signal = tr.st_signal.data in
          let guard =
            match tr.st_guard with Some g -> Some g.data | None -> None
          in
          let acts = actions_of_transition tr in
          match tr.st_action with
          | Ast.Transition te ->
              let target = resolve_target ids ~prefix te.data.trans_target in
              add_edge id target (edge_label signal guard acts)
          | Ast.Do _ -> add_edge id id (edge_label signal guard acts))
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
              emit_initial ppf ~ind:1 "__init__";
              add_edge "__init__" target (edge_label "" None acts)
          | Ast.Sm_def_state st ->
              emit_state_node ppf ids ~depth:1 ~prefix:"" st
          | Ast.Sm_def_choice c -> emit_choice_node ppf ids ~ind:1 ~prefix:"" c
          | _ -> ())
        members;
      (* All edges at top level *)
      List.iter
        (fun e ->
          if e.label = "" then
            Fmt.pf ppf {|  "%s" -> "%s";@.|} (escape_dot e.src)
              (escape_dot e.dst)
          else
            Fmt.pf ppf {|  "%s" -> "%s" [label="%s"];@.|} (escape_dot e.src)
              (escape_dot e.dst) e.label)
        (List.rev !edges);
      Fmt.pf ppf "}@."

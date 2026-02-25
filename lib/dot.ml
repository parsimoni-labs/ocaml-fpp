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

let escape_html s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string buf "&amp;"
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
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

(** Build a unified HTML edge label. Components are omitted when empty. The
    signal is bold; all parts appear on a single line: [<b>x</b> [ y ] / z]. *)
let edge_label signal guard actions =
  let parts =
    (match signal with "" -> [] | s -> [ "<b>" ^ escape_html s ^ "</b>" ])
    @ (match guard with
      | None -> []
      | Some g -> [ "[ " ^ escape_html g ^ " ]" ])
    @
    match actions with
    | [] -> []
    | acts -> [ "/ " ^ String.concat ", " (List.map escape_html acts) ]
  in
  String.concat " " parts

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
  edge [fontname="Helvetica" fontsize=9 color="#5f6368" fontcolor="#1a1a2e"];
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
    if acts = [] then []
    else [ "<b>entry</b> / " ^ String.concat ", " (List.map escape_html acts) ]
  in
  let exit_ =
    let acts =
      action_names st.Ast.state_members (function
        | Ast.State_exit _ -> true
        | _ -> false)
    in
    if acts = [] then []
    else [ "<b>exit</b> / " ^ String.concat ", " (List.map escape_html acts) ]
  in
  entry @ exit_

(** Build an HTML table label for a state with entry/exit actions. *)
let html_state_label name extras =
  let buf = Buffer.create 128 in
  Buffer.add_string buf
    {|<<table border="0" cellborder="0" cellspacing="0" cellpadding="4">|};
  Buffer.add_string buf (Fmt.str {|<tr><td>%s</td></tr>|} (escape_html name));
  Buffer.add_string buf {|<tr><td height="2"></td></tr><HR/>|};
  List.iter
    (fun line ->
      Buffer.add_string buf
        (Fmt.str
           {|<tr><td align="left"><font point-size="9">%s</font></td></tr>|}
           line))
    extras;
  Buffer.add_string buf {|</table>>|};
  Buffer.contents buf

let emit_leaf ppf ~ind ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  let extras = state_annotations st in
  indent ppf ind;
  if extras = [] then
    Fmt.pf ppf
      {|"%s" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" fontcolor="#1a1a2e" label="%s"];@.|}
      (escape_dot id)
      (escape_dot st.state_name.data)
  else
    let label = html_state_label st.state_name.data extras in
    Fmt.pf ppf
      {|"%s" [shape=box style="rounded,filled" fillcolor="#e8f0fe" color="#4285f4" fontcolor="#1a1a2e" label=%s];@.|}
      (escape_dot id) label

(* ── Choice nodes ─────────────────────────────────────────────────── *)

let emit_choice_node ppf ids ~ind ~prefix (c : Ast.def_choice) =
  let id = node_id prefix c.choice_name.data in
  indent ppf ind;
  Fmt.pf ppf
    {|"%s" [shape=diamond style=filled fillcolor="#fff8e1" color="#f9ab00" fontcolor="#1a1a2e" label="%s"];@.|}
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

(* ── Topology rendering ────────────────────────────────────────────── *)

let pp_topo_preamble ppf name =
  Fmt.pf ppf {|digraph "%s" {@.|} (escape_dot name);
  Fmt.pf ppf
    {|  compound=true;
  rankdir=LR;
  bgcolor=white;
  pad="0.4";
  node [fontname="Helvetica" fontsize=11];
  edge [fontname="Helvetica" fontsize=9 color="#5f6368" fontcolor="#1a1a2e"];
|}

let instance_style (kind : Ast.component_kind) =
  match kind with
  | Active -> ("#dcedc8", "#558b2f")
  | Passive -> ("#e8f0fe", "#4285f4")
  | Queued -> ("#fff3e0", "#e65100")

let emit_instance ppf ~ind name comp_name (kind : Ast.component_kind) =
  let fill, border = instance_style kind in
  indent ppf ind;
  if name = comp_name then
    Fmt.pf ppf
      {|"%s" [shape=box style="rounded,filled" fillcolor="%s" color="%s" fontcolor="#1a1a2e" label="%s"];@.|}
      (escape_dot name) fill border (escape_dot name)
  else
    Fmt.pf ppf
      {|"%s" [shape=box style="rounded,filled" fillcolor="%s" color="%s" fontcolor="#1a1a2e" label=<%s<br/><font point-size="9">&lt;%s&gt;</font>>];@.|}
      (escape_dot name) fill border (escape_html name) (escape_html comp_name)

(** Collect import names from the original (unflattened) topology. *)
let import_names (topo : Ast.def_topology) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_top_import qi -> (
          match qi.data with
          | Ast.Unqualified id -> Some id.data
          | Ast.Qualified _ -> Some (Ast.qual_ident_to_string qi.data))
      | _ -> None)
    topo.Ast.topo_members

(** Collect public instance names from a sub-topology (after flattening). *)
let sub_topology_instances tu name =
  let topos = Gen_ml.collect_topologies tu in
  match List.find_opt (fun t -> t.Ast.topo_name.data = name) topos with
  | None -> SSet.empty
  | Some sub ->
      let flat = Gen_ml.flatten_topology tu sub in
      List.fold_left
        (fun acc ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Topo_spec_comp_instance ci -> (
              match ci.ci_instance.data with
              | Ast.Unqualified id -> SSet.add id.data acc
              | Ast.Qualified _ ->
                  SSet.add (Ast.qual_ident_to_string ci.ci_instance.data) acc)
          | _ -> acc)
        SSet.empty flat.Ast.topo_members

let connected_instances connections =
  List.fold_left
    (fun acc (conn : Ast.connection) ->
      let from = Gen_ml.pid_inst_name conn.conn_from_port.data in
      let to_ = Gen_ml.pid_inst_name conn.conn_to_port.data in
      SSet.add from (SSet.add to_ acc))
    SSet.empty connections

let pp_import_cluster ppf instances connected inst_import imp_name =
  let imp_instances =
    List.filter
      (fun (n, _, _) -> inst_import n = Some imp_name && SSet.mem n connected)
      instances
  in
  if imp_instances <> [] then begin
    Fmt.pf ppf {|  subgraph "cluster_%s" {@.|} (escape_dot imp_name);
    Fmt.pf ppf {|    label="%s";@.|} (escape_dot imp_name);
    Fmt.pf ppf {|    style="rounded,filled";@.|};
    Fmt.pf ppf {|    fillcolor="#f8f9fa";@.|};
    Fmt.pf ppf {|    color="#5f6368";@.|};
    Fmt.pf ppf {|    fontname="Helvetica";@.|};
    List.iter
      (fun (n, _inst, comp) ->
        emit_instance ppf ~ind:2 n comp.Ast.comp_name.data comp.comp_kind)
      imp_instances;
    Fmt.pf ppf "  }@."
  end

let add_connection_edges connections =
  List.iter
    (fun (conn : Ast.connection) ->
      let from_inst = Gen_ml.pid_inst_name conn.conn_from_port.data in
      let to_inst = Gen_ml.pid_inst_name conn.conn_to_port.data in
      let from_port = conn.conn_from_port.data.pid_port.data in
      let to_port = conn.conn_to_port.data.pid_port.data in
      add_edge from_inst to_inst
        (Fmt.str "%s → %s" (escape_html from_port) (escape_html to_port)))
    connections

let pp_topology tu ppf (topo : Ast.def_topology) =
  let imports = import_names topo in
  let import_inst_sets =
    List.map (fun name -> (name, sub_topology_instances tu name)) imports
  in
  let flat = Gen_ml.flatten_topology tu topo in
  let instances = Gen_ml.resolve_topology_instances tu flat in
  let groups = Gen_ml.collect_direct_connections flat in
  let connections = Gen_ml.all_connections groups in
  let connected = connected_instances connections in
  edges := [];
  pp_topo_preamble ppf topo.Ast.topo_name.data;
  let inst_import name =
    List.find_map
      (fun (imp, set) -> if SSet.mem name set then Some imp else None)
      import_inst_sets
  in
  List.iter (pp_import_cluster ppf instances connected inst_import) imports;
  List.iter
    (fun (n, _inst, comp) ->
      if inst_import n = None && SSet.mem n connected then
        emit_instance ppf ~ind:1 n comp.Ast.comp_name.data comp.comp_kind)
    instances;
  add_connection_edges connections;
  List.iter
    (fun e ->
      if e.label = "" then
        Fmt.pf ppf {|  "%s" -> "%s";@.|} (escape_dot e.src) (escape_dot e.dst)
      else
        Fmt.pf ppf {|  "%s" -> "%s" [label=<%s> fontsize=9];@.|}
          (escape_dot e.src) (escape_dot e.dst) e.label)
    (List.rev !edges);
  Fmt.pf ppf "}@."

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
      let eid = ref 0 in
      List.iter
        (fun e ->
          if e.label = "" then
            Fmt.pf ppf {|  "%s" -> "%s";@.|} (escape_dot e.src)
              (escape_dot e.dst)
          else if e.src = e.dst then
            (* Self-loop: inline HTML label *)
            Fmt.pf ppf {|  "%s" -> "%s" [label=<%s>];@.|} (escape_dot e.src)
              (escape_dot e.dst) e.label
          else begin
            (* Cross-node: intermediate label node *)
            let id = Fmt.str "__e%d" !eid in
            incr eid;
            Fmt.pf ppf
              {|  "%s" [shape=plaintext fontcolor="#1a1a2e" fontname="Helvetica" fontsize=9 label=<%s>];@.|}
              id e.label;
            Fmt.pf ppf {|  "%s" -> "%s" [arrowhead=none];@.|} (escape_dot e.src)
              id;
            Fmt.pf ppf {|  "%s" -> "%s";@.|} id (escape_dot e.dst)
          end)
        (List.rev !edges);
      Fmt.pf ppf "}@."

(** State machine to D2 rendering.

    Produces D2 diagrams from FPP state machine definitions. D2
    (https://d2lang.com) is a modern diagramming language with clean default
    styling and native support for hierarchical containers. *)

(* ── Helpers shared with Dot ───────────────────────────────────────── *)

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

(* ── D2 emission ───────────────────────────────────────────────────── *)

let indent ppf depth =
  for _ = 1 to depth do
    Fmt.pf ppf "  "
  done

let emit_choice ppf ids ~depth ~prefix (c : Ast.def_choice) =
  let id = node_id prefix c.choice_name.data in
  indent ppf depth;
  Fmt.pf ppf "%s: %s {shape: diamond}@." id c.choice_name.data;
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
          Fmt.pf ppf "%s -> %s: %s%s@." id target guard_label acts
      | Ast.Choice_else te ->
          let target = resolve_target ids ~prefix te.data.trans_target in
          let acts = trans_expr_label te.data in
          indent ppf depth;
          Fmt.pf ppf "%s -> %s: else%s@." id target acts)
    c.choice_members

let rec emit_state ppf ids ~depth ~prefix (st : Ast.def_state) =
  let id = node_id prefix st.state_name.data in
  let has_substates = Check_env.state_has_substates st in
  (if has_substates then (
     (* Parent state: emit as a container *)
     indent ppf depth;
     Fmt.pf ppf "%s: %s {@." id st.state_name.data;
     (* Recurse into children *)
     List.iter
       (fun ann ->
         match (Ast.unannotate ann).Ast.data with
         | Ast.State_def_state sub ->
             emit_state ppf ids ~depth:(depth + 1) ~prefix:id sub
         | Ast.State_def_choice c ->
             emit_choice ppf ids ~depth:(depth + 1) ~prefix:id c
         | _ -> ())
       st.state_members;
     indent ppf depth;
     Fmt.pf ppf "}@.")
   else
     (* Leaf state: emit as a simple node *)
     let entry =
       List.filter_map
         (fun ann ->
           match (Ast.unannotate ann).Ast.data with
           | Ast.State_entry acts ->
               Some
                 ("entry / "
                 ^ String.concat ", "
                     (List.map (fun (a : Ast.ident Ast.node) -> a.data) acts))
           | _ -> None)
         st.state_members
     in
     let exit_ =
       List.filter_map
         (fun ann ->
           match (Ast.unannotate ann).Ast.data with
           | Ast.State_exit acts ->
               Some
                 ("exit / "
                 ^ String.concat ", "
                     (List.map (fun (a : Ast.ident Ast.node) -> a.data) acts))
           | _ -> None)
         st.state_members
     in
     let extras = entry @ exit_ in
     indent ppf depth;
     if extras = [] then Fmt.pf ppf "%s: %s@." id st.state_name.data
     else
       Fmt.pf ppf "%s: |md\n  %s\n  ---\n  %s\n|@." id st.state_name.data
         (String.concat "\n  " extras));
  (* Emit initial transition *)
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_initial te ->
          let target = resolve_target ids ~prefix:id te.data.trans_target in
          let acts = trans_expr_label te.data in
          indent ppf depth;
          if acts = "" then
            Fmt.pf ppf "%s -> %s: {style.stroke-dash: 3}@." id target
          else Fmt.pf ppf "%s -> %s: %s {style.stroke-dash: 3}@." id target acts
      | _ -> ())
    st.state_members;
  (* Emit transition edges *)
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> (
          let label = transition_label tr in
          match tr.st_action with
          | Ast.Transition te ->
              let target = resolve_target ids ~prefix te.data.trans_target in
              indent ppf depth;
              Fmt.pf ppf "%s -> %s: %s@." id target label
          | Ast.Do _ ->
              indent ppf depth;
              Fmt.pf ppf "%s -> %s: %s@." id id label)
      | _ -> ())
    st.state_members

(* ── Public API ────────────────────────────────────────────────────── *)

let pp ppf (sm : Ast.def_state_machine) =
  match sm.sm_members with
  | None -> ()
  | Some members ->
      let name = sm.sm_name.data in
      let ids = collect_ids members in
      Fmt.pf ppf "%s: {label: %s}@." name name;
      Fmt.pf ppf "direction: down@.";
      (* Walk SM members *)
      List.iter
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Sm_initial te ->
              let target = resolve_target ids ~prefix:"" te.data.trans_target in
              let acts = trans_expr_label te.data in
              if acts = "" then
                Fmt.pf ppf "(***) -> %s: {style.stroke-dash: 3}@." target
              else
                Fmt.pf ppf "(***) -> %s: %s {style.stroke-dash: 3}@." target
                  acts
          | Ast.Sm_def_state st -> emit_state ppf ids ~depth:0 ~prefix:"" st
          | Ast.Sm_def_choice c -> emit_choice ppf ids ~depth:0 ~prefix:"" c
          | _ -> ())
        members

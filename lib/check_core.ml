(** Core error-level checks for state machines.

    These checks detect semantic errors that must be fixed: name redefinition,
    missing or duplicate initial transitions, undefined references, unreachable
    states, choice cycles, type mismatches, and scope violations. *)

open Check_env

(* ── Name resolution ────────────────────────────────────────────────── *)

type name_kind = Action | Guard | Signal | State | Choice | Constant | Type

let string_of_kind = function
  | Action -> "action"
  | Guard -> "guard"
  | Signal -> "signal"
  | State -> "state"
  | Choice -> "choice"
  | Constant -> "constant"
  | Type -> "type"

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
      | { data = Ast.Sm_def_abs_type t; _ } -> add Type t.abs_name
      | { data = Ast.Sm_def_alias_type t; _ } -> add Type t.alias_name
      | { data = Ast.Sm_def_array a; _ } -> add Type a.array_name
      | { data = Ast.Sm_def_enum e; _ } -> add Type e.enum_name
      | { data = Ast.Sm_def_struct s; _ } -> add Type s.struct_name
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

(* ── Structural validation ──────────────────────────────────────────── *)

let validate_sm_initial ~sm_name ~sm_loc members =
  let initials =
    List.filter_map
      (fun ann ->
        match Ast.unannotate ann with
        | { Ast.data = Ast.Sm_initial _; loc; _ } -> Some loc
        | _ -> None)
      members
  in
  let diags = ref [] in
  (match initials with
  | [] ->
      let loc =
        match members with
        | ann :: _ -> (Ast.unannotate ann).Ast.loc
        | [] -> sm_loc
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

(* ── Undefined reference detection ──────────────────────────────────── *)

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

(** Suggest what kind an undefined name actually is, if it exists in a different
    namespace. *)
let hint_kind env name ~expected =
  let candidates =
    (if expected <> "action" && SMap.mem name env.actions then [ "action" ]
     else [])
    @ (if expected <> "guard" && SMap.mem name env.guards then [ "guard" ]
       else [])
    @ (if expected <> "signal" && SMap.mem name env.signals then [ "signal" ]
       else [])
    @ (if expected <> "state" && SMap.mem name env.states then [ "state" ]
       else [])
    @
    if expected <> "choice" && SMap.mem name env.choices then [ "choice" ]
    else []
  in
  match candidates with
  | [ kind ] ->
      let article =
        match kind.[0] with 'a' | 'e' | 'i' | 'o' | 'u' -> "an" | _ -> "a"
      in
      Fmt.str " (%s %s '%s' exists)" article kind name
  | _ -> ""

let verify_action ~sm_name env (id : Ast.ident Ast.node) =
  if SMap.mem id.data env.actions then []
  else
    let hint = hint_kind env id.data ~expected:"action" in
    [ error ~sm_name id.loc (Fmt.str "undefined action '%s'%s" id.data hint) ]

let verify_guard ~sm_name env (id : Ast.ident Ast.node) =
  if SMap.mem id.data env.guards then []
  else
    let hint = hint_kind env id.data ~expected:"guard" in
    [ error ~sm_name id.loc (Fmt.str "undefined guard '%s'%s" id.data hint) ]

let verify_signal ~sm_name env (id : Ast.ident Ast.node) =
  if SMap.mem id.data env.signals then []
  else
    let hint = hint_kind env id.data ~expected:"signal" in
    [ error ~sm_name id.loc (Fmt.str "undefined signal '%s'%s" id.data hint) ]

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

(* ── Duplicate signal transitions ───────────────────────────────────── *)

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

(* ── Reachability analysis ──────────────────────────────────────────── *)

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

(* ── Choice cycle detection ─────────────────────────────────────────── *)

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

(* ── Undefined type references ──────────────────────────────────────── *)

let is_builtin_type name =
  match name with
  | "U8" | "U16" | "U32" | "U64" | "I8" | "I16" | "I32" | "I64" | "F32" | "F64"
  | "bool" | "string" ->
      true
  | _ -> false

let verify_type_name ~sm_name env (tn : Ast.type_name Ast.node) =
  match tn.data with
  | Ast.Type_qual qi -> (
      let name =
        match qi.data with
        | Ast.Unqualified id -> id.data
        | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data
      in
      match String.split_on_char '.' name with
      | [ simple ] ->
          if (not (SMap.mem simple env.types)) && not (is_builtin_type simple)
          then [ error ~sm_name qi.loc (Fmt.str "undefined type '%s'" simple) ]
          else []
      | _ -> [])
  | _ -> []

let verify_type_name_opt ~sm_name env = function
  | Some tn -> verify_type_name ~sm_name env tn
  | None -> []

let undef_type_refs ~sm_name env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_action a -> verify_type_name_opt ~sm_name env a.action_type
      | Ast.Sm_def_guard g -> verify_type_name_opt ~sm_name env g.guard_type
      | Ast.Sm_def_signal s -> verify_type_name_opt ~sm_name env s.signal_type
      | Ast.Sm_def_array a -> verify_type_name ~sm_name env a.array_elt_type
      | Ast.Sm_def_enum e -> verify_type_name_opt ~sm_name env e.enum_type
      | Ast.Sm_def_struct s ->
          List.concat_map
            (fun ann ->
              let (m : Ast.struct_type_member) =
                (Ast.unannotate ann).Ast.data
              in
              verify_type_name ~sm_name env m.struct_mem_type)
            s.struct_members
      | _ -> [])
    members

(* ── Undefined constant references ──────────────────────────────────── *)

let rec expr_ident_refs (e : Ast.expr Ast.node) =
  match e.data with
  | Ast.Expr_ident id -> [ id ]
  | Ast.Expr_literal _ -> []
  | Ast.Expr_paren inner -> expr_ident_refs inner
  | Ast.Expr_unop (_, inner) -> expr_ident_refs inner
  | Ast.Expr_binop (l, _, r) -> expr_ident_refs l @ expr_ident_refs r
  | Ast.Expr_array es -> List.concat_map expr_ident_refs es
  | Ast.Expr_struct ms ->
      List.concat_map
        (fun (m : Ast.struct_member Ast.node) ->
          expr_ident_refs m.data.sm_value)
        ms
  | Ast.Expr_dot (e, _) -> expr_ident_refs e
  | Ast.Expr_subscript (e1, e2) -> expr_ident_refs e1 @ expr_ident_refs e2

let verify_expr_constants ~sm_name env (e : Ast.expr Ast.node) =
  let ids = expr_ident_refs e in
  List.concat_map
    (fun (id : Ast.ident Ast.node) ->
      if SMap.mem id.data env.constants || SMap.mem id.data env.types then []
      else [ error ~sm_name id.loc (Fmt.str "undefined constant '%s'" id.data) ])
    ids

let undef_constant_refs ~sm_name env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_constant c ->
          verify_expr_constants ~sm_name env c.const_value
      | Ast.Sm_def_array a -> (
          match a.array_default with
          | Some e -> verify_expr_constants ~sm_name env e
          | None -> [])
      | Ast.Sm_def_enum e -> (
          List.concat_map
            (fun ann ->
              let (c : Ast.def_enum_constant) = (Ast.unannotate ann).Ast.data in
              match c.enum_const_value with
              | Some e -> verify_expr_constants ~sm_name env e
              | None -> [])
            e.enum_constants
          @
          match e.enum_default with
          | Some e -> verify_expr_constants ~sm_name env e
          | None -> [])
      | Ast.Sm_def_struct s -> (
          match s.struct_default with
          | Some e -> verify_expr_constants ~sm_name env e
          | None -> [])
      | _ -> [])
    members

(* ── Type safety ────────────────────────────────────────────────────── *)

let is_numeric_type = function
  | Ast.Type_int _ | Ast.Type_float _ -> true
  | _ -> false

let is_string_default (e : Ast.expr Ast.node) =
  match e.data with Ast.Expr_literal (Ast.Lit_string _) -> true | _ -> false

let validate_defaults ~sm_name members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_array a -> (
          match a.array_default with
          | Some e when is_string_default e ->
              if is_numeric_type a.array_elt_type.data then
                [
                  error ~sm_name e.loc
                    (Fmt.str "cannot convert string to array '%s'"
                       a.array_name.data);
                ]
              else []
          | _ -> [])
      | Ast.Sm_def_enum e -> (
          match e.enum_default with
          | Some d when is_string_default d ->
              [
                error ~sm_name d.loc
                  (Fmt.str "cannot convert string to enum '%s'" e.enum_name.data);
              ]
          | _ -> [])
      | Ast.Sm_def_struct s -> (
          match s.struct_default with
          | Some ({ data = Ast.Expr_struct ms; _ } as e) ->
              let defined =
                List.map
                  (fun ann ->
                    let (m : Ast.struct_type_member) =
                      (Ast.unannotate ann).Ast.data
                    in
                    m.struct_mem_name.data)
                  s.struct_members
              in
              let provided =
                List.map
                  (fun (m : Ast.struct_member Ast.node) -> m.data.sm_name.data)
                  ms
              in
              let extra =
                List.filter (fun name -> not (List.mem name defined)) provided
              in
              if extra <> [] then
                [
                  error ~sm_name e.loc
                    (Fmt.str "default value has fields not in struct '%s'"
                       s.struct_name.data);
                ]
              else []
          | _ -> [])
      | _ -> [])
    members

let resolve_type env (tn : Ast.type_name Ast.node) =
  match tn.data with
  | Ast.Type_qual qi -> (
      let name =
        match qi.data with
        | Ast.Unqualified id -> id.data
        | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data
      in
      match SMap.find_opt name env.type_aliases with
      | Some resolved -> resolved
      | None -> tn)
  | _ -> tn

let is_numeric_resolved env tn =
  let resolved = resolve_type env tn in
  match resolved.data with
  | Ast.Type_int _ | Ast.Type_float _ -> true
  | Ast.Type_bool -> true
  | _ -> false

let validate_formats ~sm_name env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_array a -> (
          match a.array_format with
          | Some fmt ->
              if not (is_numeric_resolved env a.array_elt_type) then
                [
                  error ~sm_name fmt.loc
                    (Fmt.str
                       "invalid format: element type of array '%s' is not \
                        numeric"
                       a.array_name.data);
                ]
              else []
          | None -> [])
      | Ast.Sm_def_struct s ->
          List.concat_map
            (fun ann ->
              let (m : Ast.struct_type_member) =
                (Ast.unannotate ann).Ast.data
              in
              match m.struct_mem_format with
              | Some fmt ->
                  if not (is_numeric_resolved env m.struct_mem_type) then
                    [
                      error ~sm_name fmt.loc
                        (Fmt.str
                           "invalid format: type of member '%s' is not numeric"
                           m.struct_mem_name.data);
                    ]
                  else []
              | None -> [])
            s.struct_members
      | _ -> [])
    members

(* ── Initial transition scope validation ────────────────────────────── *)

(** Collect names of states and choices directly defined in a state. *)
let state_local_names (st : Ast.def_state) =
  let names = Hashtbl.create 8 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_state s -> Hashtbl.replace names s.state_name.data true
      | Ast.State_def_choice c -> Hashtbl.replace names c.choice_name.data true
      | _ -> ())
    st.state_members;
  names

(** Collect names of states and choices directly defined at SM top level. *)
let sm_local_names members =
  let names = Hashtbl.create 16 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_state s -> Hashtbl.replace names s.state_name.data true
      | Ast.Sm_def_choice c -> Hashtbl.replace names c.choice_name.data true
      | _ -> ())
    members;
  names

(** Follow a choice chain and collect all terminal (non-choice) targets. *)
let rec terminal_targets choice_map visited (qi : Ast.qual_ident Ast.node) =
  let name = target_name qi in
  if Hashtbl.mem visited name then []
  else (
    Hashtbl.replace visited name true;
    match Hashtbl.find_opt choice_map name with
    | None -> [ qi ]
    | Some (c : Ast.def_choice) ->
        List.concat_map
          (fun cm ->
            let te =
              match cm with
              | Ast.Choice_if (_, te) -> te
              | Ast.Choice_else te -> te
            in
            terminal_targets choice_map visited te.data.trans_target)
          c.choice_members)

let validate_initial_scope ~sm_name choice_map local_names
    (te : Ast.transition_expr Ast.node) scope_desc =
  let visited = Hashtbl.create 8 in
  let terminals = terminal_targets choice_map visited te.data.trans_target in
  List.concat_map
    (fun (qi : Ast.qual_ident Ast.node) ->
      if is_qualified_target qi then
        [
          error ~sm_name te.loc
            (Fmt.str "initial transition of %s may not target substate '%s'"
               scope_desc (target_name qi));
        ]
      else
        let name = target_name qi in
        if not (Hashtbl.mem local_names name) then
          [
            error ~sm_name te.loc
              (Fmt.str
                 "initial transition of %s must target a state or choice \
                  defined in the same scope (target '%s' is not local)"
                 scope_desc name);
          ]
        else [])
    terminals

let validate_sm_initial_scope ~sm_name members =
  let choice_map = build_choice_map members in
  let local = sm_local_names members in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_initial te ->
          validate_initial_scope ~sm_name choice_map local te "state machine"
      | _ -> [])
    members

let rec validate_state_initial_scope ~sm_name choice_map (st : Ast.def_state) =
  let local = state_local_names st in
  let self_diags =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_initial te ->
            validate_initial_scope ~sm_name choice_map local te
              (Fmt.str "state '%s'" st.state_name.data)
        | _ -> [])
      st.state_members
  in
  let nested =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_def_state sub ->
            validate_state_initial_scope ~sm_name choice_map sub
        | _ -> [])
      st.state_members
  in
  self_diags @ nested

(* ── Typed element mismatch detection ───────────────────────────────── *)

(** Type category for widening compatibility. *)
type type_cat = Cat_int of int | Cat_float of int | Cat_bool | Cat_other

let type_cat_of (tn : Ast.type_name) =
  match tn with
  | Ast.Type_int Ast.I8 -> Cat_int 8
  | Ast.Type_int Ast.I16 -> Cat_int 16
  | Ast.Type_int Ast.I32 -> Cat_int 32
  | Ast.Type_int Ast.I64 -> Cat_int 64
  | Ast.Type_int Ast.U8 -> Cat_int 8
  | Ast.Type_int Ast.U16 -> Cat_int 16
  | Ast.Type_int Ast.U32 -> Cat_int 32
  | Ast.Type_int Ast.U64 -> Cat_int 64
  | Ast.Type_float Ast.F32 -> Cat_float 32
  | Ast.Type_float Ast.F64 -> Cat_float 64
  | Ast.Type_bool -> Cat_bool
  | _ -> Cat_other

let string_of_type_name (tn : Ast.type_name) =
  match tn with
  | Ast.Type_bool -> "bool"
  | Ast.Type_int Ast.I8 -> "I8"
  | Ast.Type_int Ast.I16 -> "I16"
  | Ast.Type_int Ast.I32 -> "I32"
  | Ast.Type_int Ast.I64 -> "I64"
  | Ast.Type_int Ast.U8 -> "U8"
  | Ast.Type_int Ast.U16 -> "U16"
  | Ast.Type_int Ast.U32 -> "U32"
  | Ast.Type_int Ast.U64 -> "U64"
  | Ast.Type_float Ast.F32 -> "F32"
  | Ast.Type_float Ast.F64 -> "F64"
  | Ast.Type_string _ -> "string"
  | Ast.Type_qual qi -> Ast.qual_ident_to_string qi.data

(** Try to widen two types. Returns [Some widened] or [None] if incompatible. *)
let widen_types (a : Ast.type_name) (b : Ast.type_name) =
  if a = b then Some a
  else
    match (type_cat_of a, type_cat_of b) with
    | Cat_int wa, Cat_int wb -> if wa >= wb then Some a else Some b
    | Cat_float wa, Cat_float wb -> if wa >= wb then Some a else Some b
    | _ -> None

(** Collect incoming types flowing into each choice from transitions. *)
let collect_incoming_types env choice_map incoming members =
  let is_choice name = Hashtbl.mem choice_map name in
  let add_incoming choice_name opt_type =
    let prev =
      match Hashtbl.find_opt incoming choice_name with
      | Some l -> l
      | None -> []
    in
    Hashtbl.replace incoming choice_name (opt_type :: prev)
  in
  let visit_trans opt_type (te : Ast.transition_expr) =
    let name = target_name te.trans_target in
    if is_choice name then add_incoming name opt_type
  in
  let rec from_sm ms =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_initial te -> visit_trans None te.data
        | Ast.Sm_def_state st -> from_state st
        | _ -> ())
      ms
  and from_state (st : Ast.def_state) =
    List.iter
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_initial te -> visit_trans None te.data
        | Ast.State_transition tr -> (
            let sig_type =
              match SMap.find_opt tr.st_signal.data env.signal_types with
              | Some opt -> Option.map (fun n -> n.Ast.data) opt
              | None -> None
            in
            match tr.st_action with
            | Ast.Transition te -> visit_trans sig_type te.data
            | Ast.Do _ -> ())
        | Ast.State_def_state sub -> from_state sub
        | _ -> ())
      st.state_members
  in
  from_sm members

(** Join a list of optional types via widening. *)
let join_types types =
  List.fold_left
    (fun acc t ->
      match (acc, t) with
      | None, t -> t
      | t, None -> t
      | Some a, Some b -> (
          match widen_types a b with Some w -> Some w | None -> acc))
    None types

(** Propagate types through choice chains until stable. *)
let propagate_choice_types choice_map incoming =
  let resolved : (string, Ast.type_name option) Hashtbl.t = Hashtbl.create 16 in
  let is_choice name = Hashtbl.mem choice_map name in
  let add_incoming choice_name opt_type =
    let prev =
      match Hashtbl.find_opt incoming choice_name with
      | Some l -> l
      | None -> []
    in
    Hashtbl.replace incoming choice_name (opt_type :: prev)
  in
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter
      (fun name _c ->
        let direct =
          match Hashtbl.find_opt incoming name with Some ts -> ts | None -> []
        in
        let joined = join_types direct in
        let prev =
          match Hashtbl.find_opt resolved name with Some t -> t | None -> None
        in
        if joined <> prev then (
          Hashtbl.replace resolved name joined;
          changed := true;
          match Hashtbl.find_opt choice_map name with
          | Some (c : Ast.def_choice) ->
              List.iter
                (fun cm ->
                  let te =
                    match cm with
                    | Ast.Choice_if (_, te) -> te
                    | Ast.Choice_else te -> te
                  in
                  let tgt = target_name te.data.trans_target in
                  if is_choice tgt then add_incoming tgt joined)
                c.choice_members
          | None -> ()))
      choice_map
  done;
  resolved

(** Check for incompatible types at each choice. *)
let type_compatibility ~sm_name choice_map incoming =
  let diags = ref [] in
  Hashtbl.iter
    (fun name types ->
      let typed = List.filter_map Fun.id types in
      match typed with
      | [] -> ()
      | first :: rest ->
          List.iter
            (fun t ->
              match widen_types first t with
              | Some _ -> ()
              | None ->
                  let loc =
                    match Hashtbl.find_opt choice_map name with
                    | Some (c : Ast.def_choice) -> c.choice_name.loc
                    | None -> Ast.dummy_loc
                  in
                  diags :=
                    error ~sm_name loc
                      (Fmt.str "incompatible types at choice '%s': %s vs %s"
                         name
                         (string_of_type_name first)
                         (string_of_type_name t))
                    :: !diags)
            rest)
    incoming;
  !diags

(** Determine the context type of a choice by collecting incoming types. *)
let compute_choice_types ~sm_name env members =
  let choice_map = build_choice_map members in
  let incoming : (string, Ast.type_name option list) Hashtbl.t =
    Hashtbl.create 16
  in
  collect_incoming_types env choice_map incoming members;
  let resolved = propagate_choice_types choice_map incoming in
  let diags = type_compatibility ~sm_name choice_map incoming in
  (resolved, diags)

(** Check typed actions in an untyped or typed context. *)
let verify_action_type ~sm_name env ~context_type loc
    (actions : Ast.ident Ast.node list) =
  List.concat_map
    (fun (id : Ast.ident Ast.node) ->
      match SMap.find_opt id.data env.action_types with
      | Some (Some atype) -> (
          match context_type with
          | None ->
              [
                error ~sm_name loc
                  (Fmt.str "typed action '%s' (%s) used in untyped context"
                     id.data
                     (string_of_type_name atype.data));
              ]
          | Some ctx ->
              if atype.data = ctx then []
              else
                [
                  error ~sm_name loc
                    (Fmt.str
                       "action '%s' type %s does not match context type %s"
                       id.data
                       (string_of_type_name atype.data)
                       (string_of_type_name ctx));
                ])
      | _ -> [])
    actions

(** Check typed guard in a context. *)
let verify_guard_type ~sm_name env ~context_type loc
    (guard_opt : Ast.ident Ast.node option) =
  match guard_opt with
  | None -> []
  | Some id -> (
      match SMap.find_opt id.data env.guard_types with
      | Some (Some gtype) -> (
          match context_type with
          | None ->
              [
                error ~sm_name loc
                  (Fmt.str "typed guard '%s' (%s) used in untyped context"
                     id.data
                     (string_of_type_name gtype.data));
              ]
          | Some ctx ->
              if gtype.data = ctx then []
              else
                [
                  error ~sm_name loc
                    (Fmt.str "guard '%s' type %s does not match context type %s"
                       id.data
                       (string_of_type_name gtype.data)
                       (string_of_type_name ctx));
                ])
      | _ -> [])

let typed_element_checks ~sm_name env members =
  let choice_types, choice_diags = compute_choice_types ~sm_name env members in
  let get_choice_type name =
    match Hashtbl.find_opt choice_types name with Some t -> t | None -> None
  in
  let rec from_sm ms =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_initial te ->
            verify_action_type ~sm_name env ~context_type:None te.loc
              te.data.trans_actions
        | Ast.Sm_def_choice c ->
            let ct = get_choice_type c.choice_name.data in
            check_choice_typed ~sm_name env ~context_type:ct c
        | Ast.Sm_def_state st -> from_state st
        | _ -> [])
      ms
  and from_state (st : Ast.def_state) =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.State_initial te ->
            verify_action_type ~sm_name env ~context_type:None te.loc
              te.data.trans_actions
        | Ast.State_entry actions ->
            let loc =
              match actions with a :: _ -> a.loc | [] -> st.state_name.loc
            in
            verify_action_type ~sm_name env ~context_type:None loc actions
        | Ast.State_exit actions ->
            let loc =
              match actions with a :: _ -> a.loc | [] -> st.state_name.loc
            in
            verify_action_type ~sm_name env ~context_type:None loc actions
        | Ast.State_transition tr ->
            let sig_type =
              match SMap.find_opt tr.st_signal.data env.signal_types with
              | Some opt -> Option.map (fun n -> n.Ast.data) opt
              | None -> None
            in
            let guard_diags =
              verify_guard_type ~sm_name env ~context_type:sig_type
                tr.st_signal.loc tr.st_guard
            in
            let action_diags =
              match tr.st_action with
              | Ast.Transition te ->
                  verify_action_type ~sm_name env ~context_type:sig_type
                    tr.st_signal.loc te.data.trans_actions
              | Ast.Do actions ->
                  verify_action_type ~sm_name env ~context_type:sig_type
                    tr.st_signal.loc actions
            in
            guard_diags @ action_diags
        | Ast.State_def_choice c ->
            let ct = get_choice_type c.choice_name.data in
            check_choice_typed ~sm_name env ~context_type:ct c
        | Ast.State_def_state sub -> from_state sub
        | _ -> [])
      st.state_members
  and check_choice_typed ~sm_name env ~context_type (c : Ast.def_choice) =
    List.concat_map
      (fun cm ->
        match cm with
        | Ast.Choice_if (guard_opt, te) ->
            verify_guard_type ~sm_name env ~context_type te.loc guard_opt
            @ verify_action_type ~sm_name env ~context_type te.loc
                te.data.trans_actions
        | Ast.Choice_else te ->
            verify_action_type ~sm_name env ~context_type te.loc
              te.data.trans_actions)
      c.choice_members
  in
  choice_diags @ from_sm members

(* ── Public entry point ─────────────────────────────────────────────── *)

let run ~sm_name ~sm_loc env members =
  let dup_names = duplicate_names ~sm_name members in
  let state_dup_names =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_def_state st -> state_duplicate_names ~sm_name st
        | _ -> [])
      members
  in
  let initial = validate_sm_initial ~sm_name ~sm_loc members in
  let state_initial =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Sm_def_state st -> validate_state_initial ~sm_name st
        | _ -> [])
      members
  in
  let undef = sm_undef_refs ~sm_name env members in
  let dup_signals = collect_dup_signals ~sm_name members in
  let reachability = unreachable ~sm_name members in
  let cycles = choice_cycles ~sm_name members in
  let undef_types = undef_type_refs ~sm_name env members in
  let undef_consts = undef_constant_refs ~sm_name env members in
  let defaults = validate_defaults ~sm_name members in
  let formats = validate_formats ~sm_name env members in
  let choice_map = build_choice_map members in
  let scope =
    validate_sm_initial_scope ~sm_name members
    @ List.concat_map
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Sm_def_state st ->
              validate_state_initial_scope ~sm_name choice_map st
          | _ -> [])
        members
  in
  let typed = typed_element_checks ~sm_name env members in
  dup_names @ state_dup_names @ initial @ state_initial @ undef @ dup_signals
  @ reachability @ cycles @ undef_types @ undef_consts @ defaults @ formats
  @ scope @ typed

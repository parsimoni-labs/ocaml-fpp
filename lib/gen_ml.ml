(** State machine to OCaml code generation.

    Produces idiomatic OCaml modules from FPP state machine definitions using
    GADTs for typed signals, module types for actions and guards, and functors
    for dependency injection. *)

(* ── Name conversion ──────────────────────────────────────────────── *)

let camel_to_snake s =
  let buf = Buffer.create (String.length s + 4) in
  String.iteri
    (fun i c ->
      if Char.uppercase_ascii c = c && Char.lowercase_ascii c <> c && i > 0 then (
        Buffer.add_char buf '_';
        Buffer.add_char buf (Char.lowercase_ascii c))
      else Buffer.add_char buf (Char.lowercase_ascii c))
    s;
  Buffer.contents buf

let constructor_name s = String.capitalize_ascii s

let ocaml_type_of_fpp_type (tn : Ast.type_name) =
  match tn with
  | Type_bool -> "bool"
  | Type_int (I8 | I16 | U8 | U16) -> "int"
  | Type_int (I32 | U32) -> "int32"
  | Type_int (I64 | U64) -> "int64"
  | Type_float (F32 | F64) -> "float"
  | Type_string _ -> "string"
  | Type_qual qi -> camel_to_snake (Ast.qual_ident_to_string qi.data)

(* ── AST collection helpers ───────────────────────────────────────── *)

let collect_actions members =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_action a -> Some a
      | _ -> None)
    members

let collect_guards members =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_guard g -> Some g
      | _ -> None)
    members

let collect_signals members =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_signal s -> Some s
      | _ -> None)
    members

let collect_choices members =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_choice c -> Some c
      | _ -> None)
    members

let collect_initial members =
  List.find_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_initial i -> Some i
      | _ -> None)
    members

let state_initial (st : Ast.def_state) =
  List.find_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_initial te -> Some te
      | _ -> None)
    st.state_members

let state_entry_actions (st : Ast.def_state) =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_entry acts -> acts
      | _ -> [])
    st.state_members

let state_transitions (st : Ast.def_state) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_transition tr -> Some tr
      | _ -> None)
    st.state_members

let state_choices (st : Ast.def_state) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_def_choice c -> Some c
      | _ -> None)
    st.state_members

let target_name (qi : Ast.qual_ident Ast.node) =
  match qi.data with
  | Ast.Unqualified id -> id.data
  | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data

(* ── State hierarchy ──────────────────────────────────────────────── *)

type state_node = {
  name : string;
  state : Ast.def_state;
  children : state_node list;
}

let rec build_state_tree (st : Ast.def_state) =
  let children = Check_env.collect_substates st in
  {
    name = st.state_name.data;
    state = st;
    children = List.map build_state_tree children;
  }

(* ── Pretty-printing ──────────────────────────────────────────────── *)

let pf = Fmt.pf

(* ── State type ───────────────────────────────────────────────────── *)

let rec pp_state_variants ppf nodes =
  List.iter
    (fun node ->
      if node.children = [] then pf ppf "@,  | %s" (constructor_name node.name)
      else
        pf ppf "@,  | %s of %s"
          (constructor_name node.name)
          (camel_to_snake node.name ^ "_substate"))
    nodes

and pp_substate_types ppf nodes =
  List.iter
    (fun node ->
      if node.children <> [] then (
        pp_substate_types ppf node.children;
        pf ppf "@,@,type %s =" (camel_to_snake node.name ^ "_substate");
        pp_state_variants ppf node.children))
    nodes

let pp_state_type ppf trees =
  pp_substate_types ppf trees;
  pf ppf "@,@,type state =";
  pp_state_variants ppf trees

(* ── Signal GADT ──────────────────────────────────────────────────── *)

let signal_ocaml_type (s : Ast.def_signal) =
  match s.signal_type with
  | None -> "unit"
  | Some tn -> ocaml_type_of_fpp_type tn.data

let pp_signal_gadt ppf signals =
  if signals <> [] then (
    pf ppf "@,@,type _ signal =";
    List.iter
      (fun (s : Ast.def_signal) ->
        let ty = signal_ocaml_type s in
        pf ppf "@,  | %s : %s signal" (constructor_name s.signal_name.data) ty)
      signals;
    pf ppf "@,@,type event = Event : 'a signal * 'a -> event")

(* ── Action module type ───────────────────────────────────────────── *)

let pp_actions_sig ppf actions =
  if actions <> [] then (
    pf ppf "@,@,module type ACTIONS = sig";
    pf ppf "@,  type ctx";
    List.iter
      (fun (a : Ast.def_action) ->
        let extra =
          match a.action_type with
          | None -> ""
          | Some tn -> " -> " ^ ocaml_type_of_fpp_type tn.data
        in
        pf ppf "@,  val %s : ctx%s -> unit"
          (camel_to_snake a.action_name.data)
          extra)
      actions;
    pf ppf "@,end")

(* ── Guard module type ────────────────────────────────────────────── *)

let pp_guards_sig ppf guards =
  if guards <> [] then (
    pf ppf "@,@,module type GUARDS = sig";
    pf ppf "@,  type ctx";
    List.iter
      (fun (g : Ast.def_guard) ->
        let extra =
          match g.guard_type with
          | None -> ""
          | Some tn -> " -> " ^ ocaml_type_of_fpp_type tn.data
        in
        pf ppf "@,  val %s : ctx%s -> bool"
          (camel_to_snake g.guard_name.data)
          extra)
      guards;
    pf ppf "@,end")

(* ── State constructor expression ─────────────────────────────────── *)

(** Build the OCaml constructor expression for entering a target state. For
    nested states, wraps in parent constructors: [S (T1)]. *)
let rec state_constructor trees tgt =
  match List.find_opt (fun n -> n.name = tgt) trees with
  | Some node -> (
      if node.children = [] then constructor_name node.name
      else
        let init = state_initial node.state in
        match init with
        | Some te ->
            let sub = target_name te.data.trans_target in
            let sub_expr = state_constructor node.children sub in
            Fmt.str "%s (%s)" (constructor_name node.name) sub_expr
        | None -> (
            match node.children with
            | child :: _ ->
                Fmt.str "%s (%s)"
                  (constructor_name node.name)
                  (constructor_name child.name)
            | [] -> constructor_name node.name))
  | None -> (
      (* Search in children *)
      let found = ref None in
      List.iter
        (fun node ->
          if !found = None && node.children <> [] then
            let sub = try_find_in_children node tgt in
            if sub <> "" then
              found := Some (Fmt.str "%s (%s)" (constructor_name node.name) sub))
        trees;
      match !found with Some s -> s | None -> constructor_name tgt)

and try_find_in_children node tgt =
  match List.find_opt (fun n -> n.name = tgt) node.children with
  | Some child ->
      if child.children = [] then constructor_name child.name
      else state_constructor [ child ] tgt
  | None ->
      let found = ref "" in
      List.iter
        (fun child ->
          if !found = "" && child.children <> [] then begin
            let sub = try_find_in_children child tgt in
            if sub <> "" then
              found := Fmt.str "%s (%s)" (constructor_name child.name) sub
          end)
        node.children;
      !found

let is_choice_target all_choices name =
  List.exists
    (fun (c : Ast.def_choice) -> c.choice_name.data = name)
    all_choices

(* ── Action call helper ──────────────────────────────────────────── *)

let pp_action_call ppf (act : Ast.ident Ast.node) ~action_types =
  let name = camel_to_snake act.data in
  let has_type =
    match List.assoc_opt act.data action_types with
    | Some true -> true
    | _ -> false
  in
  if has_type then pf ppf "A.%s t.ctx _v; " name else pf ppf "A.%s t.ctx; " name

(* ── Enter functions ──────────────────────────────────────────────── *)

let pp_enter_fn ppf trees all_choices ~action_types ~keyword node =
  let name = camel_to_snake node.name in
  let entry_acts = state_entry_actions node.state in
  let ctor = state_constructor trees node.name in
  pf ppf "@,@,  %s enter_%s t =" keyword name;
  List.iter
    (fun act ->
      pf ppf "@,    ";
      pp_action_call ppf act ~action_types)
    entry_acts;
  if node.children <> [] then
    let init = state_initial node.state in
    match init with
    | Some te ->
        let sub_target = target_name te.data.trans_target in
        if is_choice_target all_choices sub_target then
          pf ppf "@,    enter_%s { t with state = %s }"
            (camel_to_snake sub_target)
            ctor
        else pf ppf "@,    { t with state = %s }" ctor
    | None -> pf ppf "@,    { t with state = %s }" ctor
  else pf ppf "@,    { t with state = %s }" ctor

let rec pp_enter_fns ppf trees all_choices ~action_types ~first ~use_rec nodes =
  List.iter
    (fun node ->
      let keyword =
        if !first && use_rec then (
          first := false;
          "let rec")
        else if !first then (
          first := false;
          "let")
        else "and"
      in
      pp_enter_fn ppf trees all_choices ~action_types ~keyword node;
      if node.children <> [] then
        pp_enter_fns ppf trees all_choices ~action_types ~first ~use_rec
          node.children)
    nodes

(* ── Choice enter functions ───────────────────────────────────────── *)

let pp_choice_transition ppf trees all_choices ~action_types acts tgt =
  List.iter
    (fun act ->
      pf ppf "@,      ";
      pp_action_call ppf act ~action_types)
    acts;
  if is_choice_target all_choices tgt then
    pf ppf "@,      enter_%s t)" (camel_to_snake tgt)
  else
    let ctor = state_constructor trees tgt in
    pf ppf "@,      { t with state = %s })" ctor

let pp_choice_fn ppf trees all_choices ~guard_types ~action_types
    (c : Ast.def_choice) =
  let name = camel_to_snake c.choice_name.data in
  pf ppf "@,@,  and enter_%s t =" name;
  List.iter
    (fun cm ->
      match cm with
      | Ast.Choice_if (guard_opt, te) ->
          let tgt = target_name te.data.trans_target in
          let acts = te.data.trans_actions in
          (match guard_opt with
          | Some g ->
              let has_type =
                match List.assoc_opt g.data guard_types with
                | Some true -> true
                | _ -> false
              in
              if has_type then
                pf ppf "@,    if G.%s t.ctx _v then (" (camel_to_snake g.data)
              else pf ppf "@,    if G.%s t.ctx then (" (camel_to_snake g.data)
          | None -> pf ppf "@,    (");
          pp_choice_transition ppf trees all_choices ~action_types acts tgt
      | Ast.Choice_else te ->
          let tgt = target_name te.data.trans_target in
          let acts = te.data.trans_actions in
          pf ppf "@,    else (";
          pp_choice_transition ppf trees all_choices ~action_types acts tgt)
    c.choice_members

(* ── Step function: state x signal dispatch ───────────────────────── *)

let pp_transition ppf trees all_choices ~action_types
    (tr : Ast.spec_state_transition) =
  match tr.st_action with
  | Ast.Transition te ->
      let tgt = target_name te.data.trans_target in
      let acts = te.data.trans_actions in
      List.iter
        (fun act ->
          pf ppf "@,        ";
          pp_action_call ppf act ~action_types)
        acts;
      if is_choice_target all_choices tgt then
        pf ppf "@,        enter_%s t" (camel_to_snake tgt)
      else
        let ctor = state_constructor trees tgt in
        pf ppf "@,        { t with state = %s }" ctor
  | Ast.Do acts ->
      List.iter
        (fun act ->
          pf ppf "@,        ";
          pp_action_call ppf act ~action_types)
        acts;
      pf ppf "@,        t"

(** Build pattern for matching a state constructor. *)
let state_match_pattern node =
  if node.children = [] then constructor_name node.name
  else Fmt.str "%s _" (constructor_name node.name)

let pp_guarded_transitions ppf trees all_choices ~action_types ~guard_types
    guarded unguarded =
  List.iteri
    (fun i tr ->
      let g = Option.get tr.Ast.st_guard in
      let has_type =
        match List.assoc_opt g.data guard_types with
        | Some true -> true
        | _ -> false
      in
      let kw = if i = 0 then "if" else "else if" in
      if has_type then
        pf ppf "@,        %s G.%s t.ctx _v then" kw (camel_to_snake g.data)
      else pf ppf "@,        %s G.%s t.ctx then" kw (camel_to_snake g.data);
      pp_transition ppf trees all_choices ~action_types tr)
    guarded;
  match unguarded with
  | [ tr ] ->
      pf ppf "@,        else";
      pp_transition ppf trees all_choices ~action_types tr
  | _ -> pf ppf "@,        else t"

let rec pp_step_cases ppf trees all_choices signals ~action_types ~guard_types
    node =
  let transitions = state_transitions node.state in
  if transitions = [] && node.children = [] then
    pf ppf "@,    | %s, _ -> t" (state_match_pattern node)
  else (
    List.iter
      (fun (s : Ast.def_signal) ->
        let matching =
          List.filter
            (fun tr -> tr.Ast.st_signal.data = s.signal_name.data)
            transitions
        in
        if matching <> [] then (
          pf ppf "@,    | %s, Event (%s, _v) ->" (state_match_pattern node)
            (constructor_name s.signal_name.data);
          let guarded =
            List.filter (fun tr -> Option.is_some tr.Ast.st_guard) matching
          in
          let unguarded =
            List.filter (fun tr -> Option.is_none tr.Ast.st_guard) matching
          in
          if guarded <> [] then
            pp_guarded_transitions ppf trees all_choices ~action_types
              ~guard_types guarded unguarded
          else
            match unguarded with
            | [ tr ] -> pp_transition ppf trees all_choices ~action_types tr
            | _ -> ()))
      signals;
    pf ppf "@,    | %s, _ -> t" (state_match_pattern node));
  List.iter
    (pp_step_cases ppf trees all_choices signals ~action_types ~guard_types)
    node.children

let pp_step ppf trees all_choices signals ~action_types ~guard_types =
  pf ppf "@,@,  let step t event =";
  pf ppf "@,    match t.state, event with";
  List.iter
    (pp_step_cases ppf trees all_choices signals ~action_types ~guard_types)
    trees

(* ── Create function helpers ──────────────────────────────────────── *)

let pp_create_static ppf ~has_actions ~has_guards ~action_types initial ctor =
  if has_actions || has_guards then (
    pf ppf "@,@,  let create ctx =";
    (match initial with
    | Some (init : Ast.spec_initial_transition) ->
        List.iter
          (fun act ->
            pf ppf "@,    ";
            pp_action_call ppf act ~action_types)
          init.data.trans_actions
    | None -> ());
    pf ppf "@,    { state = %s; ctx }" ctor)
  else (
    pf ppf "@,@,  let create () =";
    pf ppf "@,    { state = %s }" ctor)

let pp_create_dynamic ppf trees ~has_actions ~has_guards ~action_types initial =
  if has_actions || has_guards then (
    pf ppf "@,@,  let create ctx =";
    let dummy_state =
      match trees with
      | node :: _ -> constructor_name node.name
      | [] -> "assert false"
    in
    pf ppf "@,    let t = { state = %s; ctx } in" dummy_state;
    match initial with
    | Some (init : Ast.spec_initial_transition) ->
        let tgt = target_name init.data.trans_target in
        List.iter
          (fun act ->
            pf ppf "@,    ";
            pp_action_call ppf act ~action_types)
          init.data.trans_actions;
        pf ppf "@,    enter_%s t" (camel_to_snake tgt)
    | None -> pf ppf "@,    t")
  else (
    pf ppf "@,@,  let create () =";
    pf ppf "@,    { state = %s }"
      (match trees with
      | node :: _ -> constructor_name node.name
      | [] -> "assert false"))

let pp_create ppf trees ~has_actions ~has_guards ~action_types initial init_ctor
    =
  match init_ctor with
  | Some ctor ->
      pp_create_static ppf ~has_actions ~has_guards ~action_types initial ctor
  | None ->
      pp_create_dynamic ppf trees ~has_actions ~has_guards ~action_types initial

(* ── Functor ──────────────────────────────────────────────────────── *)

let pp_functor ppf trees all_choices signals ~action_types ~guard_types
    ~has_actions ~has_guards initial =
  let a_param = if has_actions then " (A : ACTIONS)" else "" in
  let g_constraint =
    if has_guards && has_actions then " (G : GUARDS with type ctx = A.ctx)"
    else if has_guards then " (G : GUARDS)"
    else ""
  in
  pf ppf "@,@,module Make%s%s : sig" a_param g_constraint;
  pf ppf "@,  type t";
  let ctx_param =
    if has_actions then "A.ctx -> "
    else if has_guards then "G.ctx -> "
    else "unit -> "
  in
  pf ppf "@,  val create : %st" ctx_param;
  pf ppf "@,  val state : t -> state";
  if signals <> [] then pf ppf "@,  val step : t -> event -> t";
  pf ppf "@,end = struct";
  if has_actions || has_guards then (
    pf ppf "@,  type ctx = %s" (if has_actions then "A.ctx" else "G.ctx");
    pf ppf "@,  type t = { state : state; ctx : ctx }")
  else pf ppf "@,  type t = { state : state }";
  pf ppf "@,@,  let state t = t.state";
  (* Enter functions *)
  let has_choices = all_choices <> [] in
  pp_enter_fns ppf trees all_choices ~action_types ~first:(ref true)
    ~use_rec:has_choices trees;
  List.iter
    (pp_choice_fn ppf trees all_choices ~guard_types ~action_types)
    all_choices;
  (* Step function *)
  if signals <> [] then
    pp_step ppf trees all_choices signals ~action_types ~guard_types;
  (* Create function *)
  let init_ctor =
    match initial with
    | Some (init : Ast.spec_initial_transition) ->
        let tgt = target_name init.data.trans_target in
        if is_choice_target all_choices tgt then None
        else Some (state_constructor trees tgt)
    | None -> None
  in
  pp_create ppf trees ~has_actions ~has_guards ~action_types initial init_ctor;
  pf ppf "@,end"

(* ── Top-level entry point ────────────────────────────────────────── *)

let pp ppf (sm : Ast.def_state_machine) =
  match sm.sm_members with
  | None -> ()
  | Some members ->
      let name = sm.sm_name.data in
      let actions = collect_actions members in
      let guards = collect_guards members in
      let signals = collect_signals members in
      let top_states = Check_env.collect_sm_states members in
      let top_choices = collect_choices members in
      let trees = List.map build_state_tree top_states in
      let rec collect_all_choices states =
        List.concat_map
          (fun (st : Ast.def_state) ->
            let local = state_choices st in
            let subs = Check_env.collect_substates st in
            local @ collect_all_choices subs)
          states
      in
      let all_choices = top_choices @ collect_all_choices top_states in
      let initial = collect_initial members in
      let action_types =
        List.map
          (fun (a : Ast.def_action) ->
            (a.action_name.data, Option.is_some a.action_type))
          actions
      in
      let guard_types =
        List.map
          (fun (g : Ast.def_guard) ->
            (g.guard_name.data, Option.is_some g.guard_type))
          guards
      in
      let has_actions = actions <> [] in
      let has_guards = guards <> [] in
      pf ppf "@[<v>(* Generated by ofpp to-ml from state machine %s *)" name;
      pp_state_type ppf trees;
      pp_signal_gadt ppf signals;
      pp_actions_sig ppf actions;
      pp_guards_sig ppf guards;
      pp_functor ppf trees all_choices signals ~action_types ~guard_types
        ~has_actions ~has_guards initial;
      pf ppf "@,@]@."

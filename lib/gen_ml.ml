(** State machine to OCaml code generation.

    Produces idiomatic OCaml modules from FPP state machine definitions using
    phantom-typed GADTs for states, module types for actions and guards, and
    functors for dependency injection.

    The generated code follows the encoding from
    {{:https://gazagnaire.org/blog/2026-02-19-nasa-fprime.html}this blog post}:
    each state is a phantom type, and the state GADT ensures that transitions
    are well-typed. *)

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

let state_exit_actions (st : Ast.def_state) =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.State_exit acts -> acts
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

(* ── Leaf state collection ────────────────────────────────────────── *)

(** Collect all states in the state machine (recursive). *)
let rec collect_all_states (st : Ast.def_state) =
  let children = Check_env.collect_substates st in
  st :: List.concat_map collect_all_states children

(** Collect leaf states (states with no substates). *)
let rec collect_leaf_states (st : Ast.def_state) =
  let children = Check_env.collect_substates st in
  if children = [] then [ st ] else List.concat_map collect_leaf_states children

(** Collect all choices from all states (recursive). *)
let rec collect_all_choices_from_states states =
  List.concat_map
    (fun (st : Ast.def_state) ->
      let local = state_choices st in
      let subs = Check_env.collect_substates st in
      local @ collect_all_choices_from_states subs)
    states

let is_choice all_choices name =
  List.exists
    (fun (c : Ast.def_choice) -> c.choice_name.data = name)
    all_choices

type resolved = Leaf of string | Choice of string

(** Resolve a target name to either a leaf state or a choice, following initial
    transitions through composite states. *)
let rec resolve_target all_states all_choices tgt =
  if is_choice all_choices tgt then Choice tgt
  else
    match
      List.find_opt
        (fun (st : Ast.def_state) -> st.state_name.data = tgt)
        all_states
    with
    | None -> Leaf tgt
    | Some st -> (
        let children = Check_env.collect_substates st in
        if children = [] then Leaf tgt
        else
          match state_initial st with
          | Some te ->
              let sub = target_name te.data.trans_target in
              resolve_target all_states all_choices sub
          | None -> (
              match children with
              | child :: _ -> Leaf child.state_name.data
              | [] -> Leaf tgt))

(** Compute the effective transitions for a leaf state: its own transitions plus
    inherited transitions from all ancestor states (leaf's own take precedence
    for the same signal). *)
let effective_transitions leaf_st all_states =
  let own = state_transitions leaf_st in
  let own_signals =
    List.map (fun (tr : Ast.spec_state_transition) -> tr.st_signal.data) own
  in
  (* Walk up ancestor chain *)
  let rec find_parent_transitions (st : Ast.def_state) =
    (* Find the parent that contains this state *)
    let parent =
      List.find_opt
        (fun (p : Ast.def_state) ->
          let subs = Check_env.collect_substates p in
          List.exists
            (fun (s : Ast.def_state) -> s.state_name.data = st.state_name.data)
            subs)
        all_states
    in
    match parent with
    | None -> []
    | Some p ->
        let parent_trs = state_transitions p in
        let inherited =
          List.filter
            (fun (tr : Ast.spec_state_transition) ->
              not (List.mem tr.st_signal.data own_signals))
            parent_trs
        in
        inherited @ find_parent_transitions p
  in
  own @ find_parent_transitions leaf_st

(** Compute entry actions for entering a leaf state: entry actions of all
    ancestor states from outermost to innermost, then the leaf's own. *)
let entry_actions_for_leaf leaf_st all_states =
  let rec ancestors (st : Ast.def_state) =
    let parent =
      List.find_opt
        (fun (p : Ast.def_state) ->
          let subs = Check_env.collect_substates p in
          List.exists
            (fun (s : Ast.def_state) -> s.state_name.data = st.state_name.data)
            subs)
        all_states
    in
    match parent with None -> [] | Some p -> p :: ancestors p
  in
  let ancestor_list = List.rev (ancestors leaf_st) in
  let ancestor_entry =
    List.concat_map (fun st -> state_entry_actions st) ancestor_list
  in
  ancestor_entry @ state_entry_actions leaf_st

(* ── Pretty-printing ──────────────────────────────────────────────── *)

let pf = Fmt.pf

let pp_phantom_types ppf leaves =
  List.iter
    (fun (st : Ast.def_state) ->
      pf ppf "@,type %s" (camel_to_snake st.state_name.data))
    leaves

let pp_state_gadt ppf leaves =
  pf ppf "@,@,type _ state =";
  List.iter
    (fun (st : Ast.def_state) ->
      pf ppf "@,  | %s : %s state"
        (constructor_name st.state_name.data)
        (camel_to_snake st.state_name.data))
    leaves;
  pf ppf "@,@,type any = State : _ state -> any"

let pp_signal_type ppf signals =
  if signals <> [] then (
    pf ppf "@,@,type signal =";
    List.iter
      (fun (s : Ast.def_signal) ->
        match s.signal_type with
        | None -> pf ppf "@,  | %s" (constructor_name s.signal_name.data)
        | Some tn ->
            pf ppf "@,  | %s of %s"
              (constructor_name s.signal_name.data)
              (ocaml_type_of_fpp_type tn.data))
      signals)

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

(* ── Choice enter functions ───────────────────────────────────────── *)

let rec pp_choice_fn ppf all_states all_choices ~action_types ~guard_types
    ~first (c : Ast.def_choice) =
  let name = camel_to_snake c.choice_name.data in
  let keyword =
    if !first then (
      first := false;
      "let rec")
    else "and"
  in
  pf ppf "@,@,  %s enter_%s t =" keyword name;
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
                pf ppf "@,    if G.%s t.ctx (* TODO: value *) then ("
                  (camel_to_snake g.data)
              else pf ppf "@,    if G.%s t.ctx then (" (camel_to_snake g.data)
          | None -> pf ppf "@,    (");
          pp_choice_body ppf all_states all_choices ~action_types acts tgt;
          pf ppf ")"
      | Ast.Choice_else te ->
          let tgt = target_name te.data.trans_target in
          let acts = te.data.trans_actions in
          pf ppf "@,    else (";
          pp_choice_body ppf all_states all_choices ~action_types acts tgt;
          pf ppf ")")
    c.choice_members

and pp_enter_target ppf all_states all_choices ~action_types ~indent tgt =
  match resolve_target all_states all_choices tgt with
  | Choice c -> pf ppf "@,%senter_%s t" indent (camel_to_snake c)
  | Leaf leaf ->
      let entry_acts =
        match
          List.find_opt
            (fun (st : Ast.def_state) -> st.state_name.data = leaf)
            all_states
        with
        | Some st -> entry_actions_for_leaf st all_states
        | None -> []
      in
      List.iter
        (fun (act : Ast.ident Ast.node) ->
          let has_type =
            match List.assoc_opt act.data action_types with
            | Some true -> true
            | _ -> false
          in
          let n = camel_to_snake act.data in
          if has_type then pf ppf "@,%sA.%s t.ctx _v;" indent n
          else pf ppf "@,%sA.%s t.ctx;" indent n)
        entry_acts;
      pf ppf "@,%s{ t with state = State %s }" indent (constructor_name leaf)

and pp_choice_body ppf all_states all_choices ~action_types acts tgt =
  List.iter
    (fun (act : Ast.ident Ast.node) ->
      let has_type =
        match List.assoc_opt act.data action_types with
        | Some true -> true
        | _ -> false
      in
      let name = camel_to_snake act.data in
      if has_type then pf ppf "@,      A.%s t.ctx (* TODO: value *); " name
      else pf ppf "@,      A.%s t.ctx; " name)
    acts;
  pp_enter_target ppf all_states all_choices ~action_types ~indent:"      " tgt

(* ── Action list helper ───────────────────────────────────────────── *)

let pp_action_list ppf ~action_types ~indent acts =
  List.iter
    (fun (act : Ast.ident Ast.node) ->
      let n = camel_to_snake act.data in
      match List.assoc_opt act.data action_types with
      | Some true -> pf ppf "@,%sA.%s t.ctx _v;" indent n
      | _ -> pf ppf "@,%sA.%s t.ctx;" indent n)
    acts

(* ── Step function ────────────────────────────────────────────────── *)

let rec pp_step ppf leaves all_states all_choices signals ~action_types
    ~guard_types =
  pf ppf "@,@,  let step t signal =";
  pf ppf "@,    match t.state, signal with";
  List.iter
    (pp_step_leaf ppf all_states all_choices signals ~action_types ~guard_types)
    leaves;
  pf ppf "@,    | _ -> t"

and pp_step_leaf ppf all_states all_choices signals ~action_types ~guard_types
    (leaf : Ast.def_state) =
  let transitions = effective_transitions leaf all_states in
  let leaf_ctor = constructor_name leaf.state_name.data in
  let exit_acts = state_exit_actions leaf in
  List.iter
    (fun (s : Ast.def_signal) ->
      let matching =
        List.filter
          (fun (tr : Ast.spec_state_transition) ->
            tr.st_signal.data = s.signal_name.data)
          transitions
      in
      if matching <> [] then (
        let sig_ctor = constructor_name s.signal_name.data in
        let sig_pat =
          match s.signal_type with
          | None -> sig_ctor
          | Some _ -> Fmt.str "%s _v" sig_ctor
        in
        pf ppf "@,    | State %s, %s ->" leaf_ctor sig_pat;
        pp_action_list ppf ~action_types ~indent:"        " exit_acts;
        let guarded =
          List.filter (fun tr -> Option.is_some tr.Ast.st_guard) matching
        in
        let unguarded =
          List.filter (fun tr -> Option.is_none tr.Ast.st_guard) matching
        in
        if guarded <> [] then
          pp_guarded ppf all_states all_choices ~action_types ~guard_types
            guarded unguarded
        else
          match unguarded with
          | [ tr ] -> pp_transition ppf all_states all_choices ~action_types tr
          | _ -> ()))
    signals;
  let n_handled =
    List.length
      (List.filter
         (fun (s : Ast.def_signal) ->
           List.exists
             (fun (tr : Ast.spec_state_transition) ->
               tr.st_signal.data = s.signal_name.data)
             transitions)
         signals)
  in
  if n_handled > 0 && n_handled < List.length signals then
    pf ppf "@,    | State %s, _ -> t" leaf_ctor

and pp_guarded ppf all_states all_choices ~action_types ~guard_types guarded
    unguarded =
  List.iteri
    (fun i (tr : Ast.spec_state_transition) ->
      let g = Option.get tr.st_guard in
      let has_type =
        match List.assoc_opt g.data guard_types with
        | Some true -> true
        | _ -> false
      in
      let kw = if i = 0 then "if" else "else if" in
      if has_type then
        pf ppf "@,        %s G.%s t.ctx _v then" kw (camel_to_snake g.data)
      else pf ppf "@,        %s G.%s t.ctx then" kw (camel_to_snake g.data);
      pp_transition ppf all_states all_choices ~action_types tr)
    guarded;
  match unguarded with
  | [ tr ] ->
      pf ppf "@,        else";
      pp_transition ppf all_states all_choices ~action_types tr
  | _ -> pf ppf "@,        else t"

and pp_transition ppf all_states all_choices ~action_types
    (tr : Ast.spec_state_transition) =
  match tr.st_action with
  | Ast.Transition te ->
      let tgt = target_name te.data.trans_target in
      pp_action_list ppf ~action_types ~indent:"          "
        te.data.trans_actions;
      pp_enter_target ppf all_states all_choices ~action_types
        ~indent:"          " tgt
  | Ast.Do acts ->
      pp_action_list ppf ~action_types ~indent:"          " acts;
      pf ppf "@,          t"

(* ── Create function ──────────────────────────────────────────────── *)

let pp_init_actions ppf ~action_types init_acts =
  List.iter
    (fun (act : Ast.ident Ast.node) ->
      let n = camel_to_snake act.data in
      match List.assoc_opt act.data action_types with
      | Some true -> pf ppf "@,    ignore (A.%s ctx);" n
      | _ -> pf ppf "@,    A.%s ctx;" n)
    init_acts

let pp_create_init ppf leaves all_states all_choices ~action_types ~mk_record
    init_acts tgt =
  match resolve_target all_states all_choices tgt with
  | Leaf leaf ->
      pp_init_actions ppf ~action_types init_acts;
      pf ppf "@,    %s" (mk_record leaf)
  | Choice c ->
      let dummy =
        match leaves with
        | leaf :: _ -> constructor_name leaf.Ast.state_name.data
        | [] -> "assert false"
      in
      pp_init_actions ppf ~action_types init_acts;
      pf ppf "@,    let t = %s in" (mk_record dummy);
      pf ppf "@,    enter_%s t" (camel_to_snake c)

let pp_create ppf leaves all_states all_choices ~has_ctx ~action_types initial =
  let ctx_param = if has_ctx then "ctx" else "()" in
  pf ppf "@,@,  let create %s =" ctx_param;
  let mk_record leaf =
    if has_ctx then Fmt.str "{ state = State %s; ctx }" (constructor_name leaf)
    else Fmt.str "{ state = State %s }" (constructor_name leaf)
  in
  match initial with
  | Some (init : Ast.spec_initial_transition) ->
      let tgt = target_name init.data.trans_target in
      pp_create_init ppf leaves all_states all_choices ~action_types ~mk_record
        init.data.trans_actions tgt
  | None -> (
      match leaves with
      | leaf :: _ -> pf ppf "@,    %s" (mk_record leaf.state_name.data)
      | [] -> pf ppf "@,    assert false")

(* ── Functor ──────────────────────────────────────────────────────── *)

let pp_functor ppf leaves all_states all_choices signals ~action_types
    ~guard_types ~has_actions ~has_guards initial =
  let a_param = if has_actions then " (A : ACTIONS)" else "" in
  let g_constraint =
    if has_guards && has_actions then " (G : GUARDS with type ctx = A.ctx)"
    else if has_guards then " (G : GUARDS)"
    else ""
  in
  let has_ctx = has_actions || has_guards in
  pf ppf "@,@,module Make%s%s : sig" a_param g_constraint;
  pf ppf "@,  type t";
  let ctx_param =
    if has_actions then "A.ctx -> "
    else if has_guards then "G.ctx -> "
    else "unit -> "
  in
  pf ppf "@,  val create : %st" ctx_param;
  pf ppf "@,  val state : t -> any";
  if signals <> [] then pf ppf "@,  val step : t -> signal -> t";
  pf ppf "@,end = struct";
  if has_ctx then
    let ctx_type = if has_actions then "A.ctx" else "G.ctx" in
    pf ppf "@,  type t = { state : any; ctx : %s }" ctx_type
  else pf ppf "@,  type t = { state : any }";
  pf ppf "@,@,  let state t = t.state";
  (* Choice enter functions *)
  let first = ref true in
  List.iter
    (pp_choice_fn ppf all_states all_choices ~action_types ~guard_types ~first)
    all_choices;
  (* Step function *)
  if signals <> [] then
    pp_step ppf leaves all_states all_choices signals ~action_types ~guard_types;
  (* Create function *)
  pp_create ppf leaves all_states all_choices ~has_ctx ~action_types initial;
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
      let all_top_states = List.concat_map collect_all_states top_states in
      let leaves = List.concat_map collect_leaf_states top_states in
      let all_choices =
        top_choices @ collect_all_choices_from_states top_states
      in
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
      pp_phantom_types ppf leaves;
      pp_state_gadt ppf leaves;
      pp_signal_type ppf signals;
      pp_actions_sig ppf actions;
      pp_guards_sig ppf guards;
      pp_functor ppf leaves all_top_states all_choices signals ~action_types
        ~guard_types ~has_actions ~has_guards initial;
      pf ppf "@,@]@."

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
  | Type_qual qi -> (
      let parts = List.map Ast.unnode (Ast.qual_ident_to_list qi.data) in
      match List.rev parts with
      | [] -> "unit"
      | [ single ] -> camel_to_snake single
      | last :: prefix ->
          let modules = List.rev_map constructor_name prefix in
          String.concat "." (modules @ [ camel_to_snake last ]))

let ocaml_keywords =
  [
    "and";
    "as";
    "assert";
    "begin";
    "class";
    "constraint";
    "do";
    "done";
    "downto";
    "else";
    "end";
    "exception";
    "external";
    "false";
    "for";
    "fun";
    "function";
    "functor";
    "if";
    "in";
    "include";
    "inherit";
    "initializer";
    "land";
    "lazy";
    "let";
    "lor";
    "lxor";
    "match";
    "method";
    "mod";
    "module";
    "mutable";
    "new";
    "nonrec";
    "object";
    "of";
    "open";
    "or";
    "private";
    "rec";
    "sig";
    "struct";
    "then";
    "to";
    "true";
    "try";
    "type";
    "val";
    "virtual";
    "when";
    "while";
    "with";
  ]

let sanitize_ident name =
  let s = camel_to_snake name in
  let s = if s <> "" && s.[0] >= '0' && s.[0] <= '9' then "_" ^ s else s in
  if List.mem s ocaml_keywords then s ^ "_" else s

let ocaml_variant_of_const name =
  let title_case s =
    if s = "" then s
    else
      String.make 1 (Char.uppercase_ascii s.[0])
      ^ String.lowercase_ascii (String.sub s 1 (String.length s - 1))
  in
  String.concat "_" (List.map title_case (String.split_on_char '_' name))

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
              (* Scope to children to avoid infinite loops when parent and
                 child share the same name (state shadowing). *)
              let child_states = List.concat_map collect_all_states children in
              resolve_target child_states all_choices sub
          | None -> (
              match children with
              | child :: _ -> Leaf child.state_name.data
              | [] -> Leaf tgt))

(** Like {!resolve_target} but also collects the initial-transition actions
    encountered along the way (for use in [create]). *)
let rec resolve_target_with_actions all_states all_choices tgt =
  if is_choice all_choices tgt then (Choice tgt, [])
  else
    match
      List.find_opt
        (fun (st : Ast.def_state) -> st.state_name.data = tgt)
        all_states
    with
    | None -> (Leaf tgt, [])
    | Some st -> (
        let children = Check_env.collect_substates st in
        if children = [] then (Leaf tgt, [])
        else
          match state_initial st with
          | Some te ->
              let sub = target_name te.data.trans_target in
              let child_states = List.concat_map collect_all_states children in
              let resolved, deeper_acts =
                resolve_target_with_actions child_states all_choices sub
              in
              (resolved, te.data.trans_actions @ deeper_acts)
          | None -> (
              match children with
              | child :: _ -> (Leaf child.state_name.data, [])
              | [] -> (Leaf tgt, [])))

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

(* ── Type definitions ─────────────────────────────────────────────── *)

let pp_enum ppf (e : Ast.def_enum) =
  let name = sanitize_ident e.enum_name.data in
  pf ppf "@,@,type %s =" name;
  List.iter
    (fun ann ->
      let (c : Ast.def_enum_constant) = (Ast.unannotate ann).Ast.data in
      pf ppf "@,  | %s" (ocaml_variant_of_const c.enum_const_name.data))
    e.enum_constants

let pp_struct_def ppf (s : Ast.def_struct) =
  let name = sanitize_ident s.struct_name.data in
  pf ppf "@,@,type %s = {" name;
  List.iter
    (fun ann ->
      let (m : Ast.struct_type_member) = (Ast.unannotate ann).Ast.data in
      let t = ocaml_type_of_fpp_type m.struct_mem_type.data in
      let t =
        match m.struct_mem_size with None -> t | Some _ -> t ^ " array"
      in
      pf ppf "@,  %s : %s;" (sanitize_ident m.struct_mem_name.data) t)
    s.struct_members;
  pf ppf "@,}"

let pp_array_def ppf (a : Ast.def_array) =
  let name = sanitize_ident a.array_name.data in
  let t = ocaml_type_of_fpp_type a.array_elt_type.data in
  pf ppf "@,@,type %s = %s array" name t

let pp_alias_type_def ppf (a : Ast.def_alias_type) =
  let name = sanitize_ident a.alias_name.data in
  let t = ocaml_type_of_fpp_type a.alias_type.data in
  pf ppf "@,@,type %s = %s" name t

let pp_type_defs ppf members =
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Sm_def_enum e -> pp_enum ppf e
      | Ast.Sm_def_struct s -> pp_struct_def ppf s
      | Ast.Sm_def_array a -> pp_array_def ppf a
      | Ast.Sm_def_alias_type a -> pp_alias_type_def ppf a
      | _ -> ())
    members

(* ── Phantom types ───────────────────────────────────────────────── *)

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

(** Check whether any choice targets another choice (needs [let rec]). *)
let choices_need_rec all_choices =
  List.exists
    (fun (c : Ast.def_choice) ->
      List.exists
        (fun cm ->
          let tgt =
            match cm with
            | Ast.Choice_if (_, te) -> target_name te.data.trans_target
            | Ast.Choice_else te -> target_name te.data.trans_target
          in
          is_choice all_choices tgt)
        c.choice_members)
    all_choices

let rec pp_choice_fn ppf all_states all_choices ~action_types ~guard_types
    ~has_ctx ~needs_rec ~first (c : Ast.def_choice) =
  let name = camel_to_snake c.choice_name.data in
  let keyword =
    if !first then (
      first := false;
      if needs_rec then "let rec" else "let")
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
          pp_choice_body ppf all_states all_choices ~action_types ~has_ctx acts
            tgt;
          pf ppf ")"
      | Ast.Choice_else te ->
          let tgt = target_name te.data.trans_target in
          let acts = te.data.trans_actions in
          pf ppf "@,    else (";
          pp_choice_body ppf all_states all_choices ~action_types ~has_ctx acts
            tgt;
          pf ppf ")")
    c.choice_members

and pp_enter_target ppf all_states all_choices ~action_types ~has_ctx ~indent
    tgt =
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
      let ctor = constructor_name leaf in
      if has_ctx then pf ppf "@,%s{ t with state = State %s }" indent ctor
      else pf ppf "@,%s{ state = State %s }" indent ctor

and pp_choice_body ppf all_states all_choices ~action_types ~has_ctx acts tgt =
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
  pp_enter_target ppf all_states all_choices ~action_types ~has_ctx
    ~indent:"      " tgt

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
    ~guard_types ~has_ctx =
  pf ppf "@,@,  let step t signal =";
  pf ppf "@,    match t.state, signal with";
  List.iter
    (pp_step_leaf ppf all_states all_choices signals ~action_types ~guard_types
       ~has_ctx)
    leaves;
  (* Only emit final catch-all if some leaf has no handled signals at all *)
  let needs_final_catchall =
    List.exists
      (fun (leaf : Ast.def_state) ->
        let trs = effective_transitions leaf all_states in
        not
          (List.exists
             (fun (s : Ast.def_signal) ->
               List.exists
                 (fun (tr : Ast.spec_state_transition) ->
                   tr.st_signal.data = s.signal_name.data)
                 trs)
             signals))
      leaves
  in
  if needs_final_catchall then pf ppf "@,    | _ -> t"

and pp_step_leaf ppf all_states all_choices signals ~action_types ~guard_types
    ~has_ctx (leaf : Ast.def_state) =
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
            ~has_ctx guarded unguarded
        else
          match unguarded with
          | [ tr ] ->
              pp_transition ppf all_states all_choices ~action_types ~has_ctx tr
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

and pp_guarded ppf all_states all_choices ~action_types ~guard_types ~has_ctx
    guarded unguarded =
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
      pp_transition ppf all_states all_choices ~action_types ~has_ctx tr)
    guarded;
  match unguarded with
  | [ tr ] ->
      pf ppf "@,        else";
      pp_transition ppf all_states all_choices ~action_types ~has_ctx tr
  | _ -> pf ppf "@,        else t"

and pp_transition ppf all_states all_choices ~action_types ~has_ctx
    (tr : Ast.spec_state_transition) =
  match tr.st_action with
  | Ast.Transition te ->
      let tgt = target_name te.data.trans_target in
      pp_action_list ppf ~action_types ~indent:"          "
        te.data.trans_actions;
      pp_enter_target ppf all_states all_choices ~action_types ~has_ctx
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
  let resolved, deeper_acts =
    resolve_target_with_actions all_states all_choices tgt
  in
  let all_acts = init_acts @ deeper_acts in
  match resolved with
  | Leaf leaf ->
      pp_init_actions ppf ~action_types all_acts;
      pf ppf "@,    %s" (mk_record leaf)
  | Choice c ->
      let dummy =
        match leaves with
        | leaf :: _ -> constructor_name leaf.Ast.state_name.data
        | [] -> "assert false"
      in
      pp_init_actions ppf ~action_types all_acts;
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
  let needs_rec = choices_need_rec all_choices in
  List.iter
    (pp_choice_fn ppf all_states all_choices ~action_types ~guard_types ~has_ctx
       ~needs_rec ~first)
    all_choices;
  (* Step function *)
  if signals <> [] then
    pp_step ppf leaves all_states all_choices signals ~action_types ~guard_types
      ~has_ctx;
  (* Create function *)
  pp_create ppf leaves all_states all_choices ~has_ctx ~action_types initial;
  pf ppf "@,end"

(* ── Top-level entry point (state machines) ──────────────────────── *)

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
      pp_type_defs ppf members;
      pp_phantom_types ppf leaves;
      pp_state_gadt ppf leaves;
      pp_signal_type ppf signals;
      pp_actions_sig ppf actions;
      pp_guards_sig ppf guards;
      pp_functor ppf leaves all_top_states all_choices signals ~action_types
        ~guard_types ~has_actions ~has_guards initial;
      pf ppf "@]@."

(* ── Annotation parsing ──────────────────────────────────────────── *)

type ocaml_annots = { functor_path : string option }

let starts_with ~prefix s =
  let plen = String.length prefix in
  String.length s >= plen && String.sub s 0 plen = prefix

let parse_ocaml_annotations annots =
  List.fold_left
    (fun acc s ->
      let s = String.trim s in
      if starts_with ~prefix:"ocaml.functor " s then
        let v = String.trim (String.sub s 14 (String.length s - 14)) in
        { functor_path = Some v }
      else acc)
    { functor_path = None } annots

(** Extract pre-annotations for a component definition from tu_members. *)
let component_annots tu comp_name =
  let rec search members =
    List.find_map
      (fun ((pre, node, _) : Ast.module_member Ast.node Ast.annotated) ->
        match node.Ast.data with
        | Ast.Mod_def_component c when c.comp_name.data = comp_name -> Some pre
        | Ast.Mod_def_module m -> search m.Ast.module_members
        | _ -> None)
      members
  in
  Option.value ~default:[] (search tu.Ast.tu_members)

(* ── Topology code generation ────────────────────────────────────── *)

(** Resolve a topology instance name to its component instance definition. *)
let resolve_comp_instance tu inst_qi =
  let inst_name =
    match inst_qi with
    | Ast.Unqualified id -> id.data
    | Ast.Qualified _ -> Ast.qual_ident_to_string inst_qi
  in
  let instances =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Mod_def_component_instance ci -> Some ci
        | Ast.Mod_def_module m ->
            List.find_map
              (fun ann2 ->
                match (Ast.unannotate ann2).Ast.data with
                | Ast.Mod_def_component_instance ci -> Some ci
                | _ -> None)
              m.Ast.module_members
        | _ -> None)
      tu.Ast.tu_members
  in
  List.find_opt
    (fun (ci : Ast.def_component_instance) -> ci.inst_name.data = inst_name)
    instances

(** Resolve a component qualified identifier to its definition. *)
let resolve_component tu comp_qi =
  let comp_name =
    match comp_qi with
    | Ast.Unqualified id -> id.data
    | Ast.Qualified _ ->
        let parts = Ast.qual_ident_to_list comp_qi in
        (List.nth parts (List.length parts - 1)).data
  in
  let components =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Mod_def_component c -> Some c
        | Ast.Mod_def_module m ->
            List.find_map
              (fun ann2 ->
                match (Ast.unannotate ann2).Ast.data with
                | Ast.Mod_def_component c -> Some c
                | _ -> None)
              m.Ast.module_members
        | _ -> None)
      tu.Ast.tu_members
  in
  List.find_opt
    (fun (c : Ast.def_component) -> c.comp_name.data = comp_name)
    components

(** Collect general ports from a component. *)
let collect_general_ports (comp : Ast.def_component) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Ast.Port_general p) -> Some p
      | _ -> None)
    comp.comp_members

(** Collect general ports with their pre-annotations preserved. *)
let collect_general_ports_annotated (comp : Ast.def_component) =
  List.filter_map
    (fun ((pre, node, _) : Ast.component_member Ast.node Ast.annotated) ->
      match node.Ast.data with
      | Ast.Comp_spec_port_instance (Ast.Port_general p) -> Some (pre, p)
      | _ -> None)
    comp.comp_members

(** Whether a component is active (has async ports or is declared active). *)
let is_active_component (comp : Ast.def_component) =
  comp.comp_kind = Active
  || List.exists
       (fun ann ->
         match (Ast.unannotate ann).Ast.data with
         | Ast.Comp_spec_port_instance (Ast.Port_general p) ->
             p.gen_kind = Async_input
         | _ -> false)
       comp.comp_members

(* ── Port-based module type generation ────────────────────────────── *)

(** Resolve a port definition by name from the translation unit. *)
let resolve_port_def tu port_qi =
  let port_name =
    match port_qi with
    | Ast.Unqualified id -> id.data
    | Ast.Qualified _ -> Ast.qual_ident_to_string port_qi
  in
  let ports =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Mod_def_port p -> Some p
        | Ast.Mod_def_module m ->
            List.find_map
              (fun ann2 ->
                match (Ast.unannotate ann2).Ast.data with
                | Ast.Mod_def_port p -> Some p
                | _ -> None)
              m.Ast.module_members
        | _ -> None)
      tu.Ast.tu_members
  in
  List.find_opt (fun (p : Ast.def_port) -> p.port_name.data = port_name) ports

(** Generate OCaml type string for a port's formal parameters and return type.
    Returns [(param_types, return_type)]. *)
let port_type_parts (port_def : Ast.def_port) =
  let params =
    List.map
      (fun ann ->
        let (fp : Ast.formal_param) = (Ast.unannotate ann).Ast.data in
        ocaml_type_of_fpp_type fp.fp_type.data)
      port_def.port_params
  in
  let ret =
    match port_def.port_return with
    | Some tn -> ocaml_type_of_fpp_type tn.data
    | None -> "unit"
  in
  (params, ret)

(** Pretty-print a module type generated from a component's input ports. For
    each [sync input port name: PortType], generates
    [val name : t -> param_types -> return_type]. *)
let pp_port_module_type ppf tu (comp : Ast.def_component) =
  let name = String.uppercase_ascii (camel_to_snake comp.comp_name.data) in
  pf ppf "@,@,module type %s = sig" name;
  pf ppf "@,  type t";
  let ports = collect_general_ports comp in
  let input_ports =
    List.filter
      (fun (p : Ast.port_instance_general) -> p.gen_kind <> Output)
      ports
  in
  List.iter
    (fun (p : Ast.port_instance_general) ->
      let port_name = sanitize_ident p.gen_name.data in
      match p.gen_port with
      | Some port_qi -> (
          match resolve_port_def tu port_qi.data with
          | Some port_def ->
              let param_types, ret = port_type_parts port_def in
              pf ppf "@,  val %s : t" port_name;
              List.iter (fun t -> pf ppf " -> %s" t) param_types;
              pf ppf " -> %s" ret
          | None -> pf ppf "@,  val %s : t -> unit" port_name)
      | None -> pf ppf "@,  val %s : t -> unit" port_name)
    input_ports;
  pf ppf "@,end"

(* ── Topology resolution ─────────────────────────────────────────── *)

(** Resolve topology instances to (instance_name, component_instance, component)
    triples. *)
let resolve_topology_instances tu (topo : Ast.def_topology) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_comp_instance ci -> (
          let inst_name =
            match ci.ci_instance.data with
            | Ast.Unqualified id -> id.data
            | Ast.Qualified _ -> Ast.qual_ident_to_string ci.ci_instance.data
          in
          match resolve_comp_instance tu ci.ci_instance.data with
          | None -> None
          | Some comp_inst -> (
              match resolve_component tu comp_inst.inst_component.data with
              | None -> None
              | Some comp -> Some (inst_name, comp_inst, comp)))
      | _ -> None)
    topo.topo_members

(** Collect direct connections from a topology. *)
let collect_direct_connections (topo : Ast.def_topology) =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_connection_graph
          (Ast.Graph_direct { graph_connections; _ }) ->
          List.map
            (fun conn_ann -> (Ast.unannotate conn_ann).Ast.data)
            graph_connections
      | _ -> [])
    topo.topo_members

(** Collect pattern connections from a topology (emitted as comments). *)
let collect_pattern_connections (topo : Ast.def_topology) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_connection_graph
          (Ast.Graph_pattern { pattern_kind; pattern_source; pattern_targets })
        ->
          Some (pattern_kind, pattern_source, pattern_targets)
      | _ -> None)
    topo.topo_members

(** Extract instance name from a port instance identifier. *)
let pid_inst_name (pid : Ast.port_instance_id) =
  match pid.pid_component.data with
  | Ast.Unqualified id -> id.data
  | Ast.Qualified _ -> Ast.qual_ident_to_string pid.pid_component.data

(** Collect the names of instances that [inst_name] connects to. *)
let connection_targets inst_name connections =
  List.filter_map
    (fun (conn : Ast.connection) ->
      if pid_inst_name conn.conn_from_port.data = inst_name then
        Some (pid_inst_name conn.conn_to_port.data)
      else None)
    connections

(** Topologically sort instances: instances with no output ports first, then
    those that connect only to already-placed instances. Falls back to input
    order when no strict ordering is possible. *)
let topo_sort_instances resolved connections =
  let instance_outputs =
    List.map
      (fun (inst_name, _ci, _comp) ->
        (inst_name, connection_targets inst_name connections))
      resolved
  in
  let placed = ref [] in
  let remaining = ref resolved in
  let changed = ref true in
  while !changed do
    changed := false;
    let new_remaining = ref [] in
    let targets_of name =
      Option.value ~default:[] (List.assoc_opt name instance_outputs)
    in
    List.iter
      (fun ((inst_name, _, _) as entry) ->
        let all_placed =
          List.for_all
            (fun t -> List.exists (fun (n, _, _) -> n = t) !placed)
            (targets_of inst_name)
        in
        if all_placed then (
          placed := !placed @ [ entry ];
          changed := true)
        else new_remaining := !new_remaining @ [ entry ])
      !remaining;
    remaining := !new_remaining
  done;
  !placed @ !remaining

(** Connections from a specific instance and port. *)
let conns_from inst_name port_name connections =
  List.filter
    (fun (conn : Ast.connection) ->
      let from_port = conn.conn_from_port.data.pid_port.data in
      pid_inst_name conn.conn_from_port.data = inst_name
      && camel_to_snake from_port = port_name)
    connections

(** Compute unique target instances for an instance from its output port
    connections. Returns [(target_inst_name, target_component)] pairs, deduped
    and ordered by first occurrence. *)
let target_instances inst_name (comp : Ast.def_component) connections sorted =
  let ports = collect_general_ports comp in
  let outputs =
    List.filter
      (fun (p : Ast.port_instance_general) -> p.gen_kind = Output)
      ports
  in
  let seen = Hashtbl.create 4 in
  let targets = ref [] in
  List.iter
    (fun (outp : Ast.port_instance_general) ->
      let port_name = camel_to_snake outp.gen_name.data in
      let conns = conns_from inst_name port_name connections in
      List.iter
        (fun (conn : Ast.connection) ->
          let to_inst = pid_inst_name conn.conn_to_port.data in
          if not (Hashtbl.mem seen to_inst) then (
            Hashtbl.add seen to_inst ();
            match List.find_opt (fun (n, _, _) -> n = to_inst) sorted with
            | Some (_, _, target_comp) ->
                targets := (to_inst, target_comp) :: !targets
            | None -> ()))
        conns)
    outputs;
  List.rev !targets

(** Pretty-print a module type for a component: just [type t]. *)
let pp_component_sig ppf (comp : Ast.def_component) =
  let name = String.uppercase_ascii (camel_to_snake comp.comp_name.data) in
  pf ppf "@,@,module type %s = sig" name;
  pf ppf "@,  type t";
  pf ppf "@,end"

(** Pretty-print the connect function body. Leaf instances (no outgoing
    connections) become parameters; non-leaf instances are bound via their
    [connect] function. *)
let pp_topo_connect_body ppf sorted connections =
  let has_active =
    List.exists
      (fun (_, _, (comp : Ast.def_component)) -> is_active_component comp)
      sorted
  in
  let leaf_params =
    List.filter_map
      (fun (inst_name, _ci, (comp : Ast.def_component)) ->
        if target_instances inst_name comp connections sorted = [] then
          Some (sanitize_ident inst_name)
        else None)
      sorted
  in
  let params = String.concat " " leaf_params in
  if has_active then (
    pf ppf "@,  let connect %s =" params;
    pf ppf "@,    let open Lwt.Syntax in")
  else pf ppf "@,  let connect %s =" params;
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp connections sorted in
      if targets <> [] then (
        let inst_var = sanitize_ident inst_name in
        let mod_name = constructor_name inst_name in
        let active = is_active_component comp in
        let bind = if active then "let* " else "let " in
        pf ppf "@,    %s%s = %s.connect" bind inst_var mod_name;
        List.iter
          (fun (target_inst, _) -> pf ppf " %s" (sanitize_ident target_inst))
          targets;
        pf ppf " in"))
    sorted;
  let fields =
    List.map (fun (inst_name, _, _) -> sanitize_ident inst_name) sorted
  in
  if has_active then
    pf ppf "@,    Lwt.return { %s }" (String.concat "; " fields)
  else pf ppf "@,    { %s }" (String.concat "; " fields)

(** Pretty-print a topology functor. Each instance becomes a module parameter.
    Leaf instances (no outgoing connections) use their named module type
    directly. Non-leaf instances carry an inline [val connect] whose arguments
    are the dependency instances. *)
let pp_topology_functor ppf topo sorted connections =
  pf ppf "@,@,module Make";
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let mod_name = constructor_name inst_name in
      let comp_type =
        String.uppercase_ascii (camel_to_snake comp.comp_name.data)
      in
      let targets = target_instances inst_name comp connections sorted in
      if targets = [] then pf ppf "@,  (%s : %s)" mod_name comp_type
      else
        let active = is_active_component comp in
        let connect_ret = if active then "t Lwt.t" else "t" in
        pf ppf "@,  (%s : sig include %s val connect :" mod_name comp_type;
        List.iter
          (fun (target_inst, _) ->
            pf ppf " %s.t ->" (constructor_name target_inst))
          targets;
        pf ppf " %s end)" connect_ret)
    sorted;
  pf ppf " = struct";
  pf ppf "@,  type t = {";
  List.iter
    (fun (inst_name, _ci, _comp) ->
      let mod_name = constructor_name inst_name in
      pf ppf " %s : %s.t;" (sanitize_ident inst_name) mod_name)
    sorted;
  pf ppf " }";
  pp_topo_connect_body ppf sorted connections;
  (* Pattern connections as comments *)
  let patterns = collect_pattern_connections topo in
  if patterns <> [] then (
    pf ppf "@,@,  (* Pattern connections (framework-level):";
    List.iter
      (fun (pk, source, targets) ->
        let kind =
          match pk with
          | Ast.Pattern_command -> "command"
          | Pattern_event -> "event"
          | Pattern_health -> "health"
          | Pattern_param -> "param"
          | Pattern_telemetry -> "telemetry"
          | Pattern_text_event -> "text_event"
          | Pattern_time -> "time"
        in
        pf ppf "@,     %s: %s -> [%s]" kind
          (Ast.qual_ident_to_string source.Ast.data)
          (String.concat ", "
             (List.map (fun qi -> Ast.qual_ident_to_string qi.Ast.data) targets)))
      patterns;
    pf ppf " *)");
  pf ppf "@,end"

(* ── Annotated (functor-application) topology mode ───────────────── *)

(** Input ports on [comp] that have no incoming connection for [inst_name] AND
    are annotated with [@ ocaml.param]. Only these surface as labeled parameters
    of the generated [connect] function — plain data-flow ports that happen to
    be unconnected are silently ignored. *)
let unconnected_input_ports inst_name (comp : Ast.def_component) connections =
  let annotated_input_ports =
    List.filter_map
      (fun (pre, (p : Ast.port_instance_general)) ->
        if
          p.gen_kind <> Output
          && List.exists (fun s -> String.trim s = "ocaml.param") pre
        then Some p
        else None)
      (collect_general_ports_annotated comp)
  in
  List.filter
    (fun (p : Ast.port_instance_general) ->
      let port_name = camel_to_snake p.gen_name.data in
      not
        (List.exists
           (fun (conn : Ast.connection) ->
             pid_inst_name conn.conn_to_port.data = inst_name
             && camel_to_snake conn.conn_to_port.data.pid_port.data = port_name)
           connections))
    annotated_input_ports

(** Emit functor applications for non-leaf instances inside the Make struct. *)
let pp_functor_apps ppf tu sorted connections =
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp connections sorted in
      if targets <> [] then (
        let mod_name = constructor_name inst_name in
        let ca =
          parse_ocaml_annotations (component_annots tu comp.comp_name.data)
        in
        let functor_path =
          match ca.functor_path with
          | Some s -> s
          | None -> constructor_name comp.comp_name.data ^ ".Make"
        in
        pf ppf "@,  module %s = %s" mod_name functor_path;
        List.iter
          (fun (target_inst, _) -> pf ppf "(%s)" (constructor_name target_inst))
          targets))
    sorted

(** Emit individual connect calls for non-leaf, non-passive instances. Passive
    (module-only) components get functor applications but no connect. *)
let pp_annotated_connect_calls ppf sorted connections =
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      if comp.comp_kind = Passive then ()
      else
        let targets = target_instances inst_name comp connections sorted in
        if targets <> [] then (
          let inst_var = sanitize_ident inst_name in
          let mod_name = constructor_name inst_name in
          let active = is_active_component comp in
          let bind = if active then "let* " else "let " in
          let config_ports =
            unconnected_input_ports inst_name comp connections
          in
          pf ppf "@,    %s%s = %s.connect" bind inst_var mod_name;
          List.iter
            (fun (p : Ast.port_instance_general) ->
              pf ppf " ~%s" (sanitize_ident p.gen_name.data))
            config_ports;
          (* Skip passive targets — they have no runtime value *)
          List.iter
            (fun (target_inst, (tc : Ast.def_component)) ->
              if tc.comp_kind <> Passive then
                pf ppf " %s" (sanitize_ident target_inst))
            targets;
          pf ppf " in"))
    sorted

(** Emit the connect function for annotated topology mode. Passive (module-only)
    components are excluded from the connect body, record fields, and functor
    parameters. *)
let pp_annotated_connect ppf sorted connections =
  let concrete =
    List.filter
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      sorted
  in
  let has_active =
    List.exists
      (fun (_, _, (comp : Ast.def_component)) -> is_active_component comp)
      concrete
  in
  (* Collect labeled args: unconnected input ports from non-leaf instances *)
  let labeled_args =
    List.concat_map
      (fun (inst_name, _ci, (comp : Ast.def_component)) ->
        let targets = target_instances inst_name comp connections sorted in
        if targets <> [] then
          List.map
            (fun (p : Ast.port_instance_general) ->
              sanitize_ident p.gen_name.data)
            (unconnected_input_ports inst_name comp connections)
        else [])
      concrete
  in
  let leaf_params =
    List.filter_map
      (fun (inst_name, _ci, (comp : Ast.def_component)) ->
        if target_instances inst_name comp connections sorted = [] then
          Some (sanitize_ident inst_name)
        else None)
      concrete
  in
  pf ppf "@,@,  let connect";
  List.iter (fun arg -> pf ppf " ~%s" arg) labeled_args;
  List.iter (fun p -> pf ppf " %s" p) leaf_params;
  pf ppf " =";
  if has_active then pf ppf "@,    let open Lwt.Syntax in";
  pp_annotated_connect_calls ppf sorted connections;
  let fields =
    List.map (fun (inst_name, _, _) -> sanitize_ident inst_name) concrete
  in
  if has_active then
    pf ppf "@,    Lwt.return { %s }" (String.concat "; " fields)
  else pf ppf "@,    { %s }" (String.concat "; " fields)

(** Pretty-print an annotated topology in functor-application mode. Passive
    components are module-only: they get functor applications but no record
    fields, connect calls, or Make parameters. *)
let pp_topology_annotated ppf tu sorted connections =
  let concrete =
    List.filter
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      sorted
  in
  pf ppf "@,@,module Make";
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp connections sorted in
      if targets = [] then
        let mod_name = constructor_name inst_name in
        let constraint_ =
          String.uppercase_ascii (camel_to_snake comp.comp_name.data)
        in
        pf ppf "@,  (%s : %s)" mod_name constraint_)
    concrete;
  pf ppf " = struct";
  pp_functor_apps ppf tu sorted connections;
  pf ppf "@,@,  type t = {";
  List.iter
    (fun (inst_name, _ci, _comp) ->
      let mod_name = constructor_name inst_name in
      pf ppf " %s : %s.t;" (sanitize_ident inst_name) mod_name)
    concrete;
  pf ppf " }";
  pp_annotated_connect ppf sorted connections;
  pf ppf "@,end"

(** Whether a topology should use functor-application mode: any non-leaf
    non-passive component triggers it. The [@ ocaml.functor] annotation is only
    needed to override the default [ComponentName.Make] path. *)
let is_functor_mode sorted connections =
  List.exists
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      comp.comp_kind <> Passive
      && connection_targets inst_name connections <> [])
    sorted

(** Pretty-print a full topology as OCaml code. *)
let pp_topology tu ppf (topo : Ast.def_topology) =
  let resolved = resolve_topology_instances tu topo in
  let connections = collect_direct_connections topo in
  let sorted = topo_sort_instances resolved connections in
  pf ppf "@[<v>(* Generated by ofpp to-ml from topology %s *)"
    topo.topo_name.data;
  (if is_functor_mode sorted connections then
     pp_topology_annotated ppf tu sorted connections
   else
     let seen = Hashtbl.create 8 in
     let unique_comps =
       List.filter_map
         (fun (_inst_name, _ci, (comp : Ast.def_component)) ->
           if Hashtbl.mem seen comp.comp_name.data then None
           else (
             Hashtbl.add seen comp.comp_name.data ();
             Some comp))
         sorted
     in
     List.iter (pp_component_sig ppf) unique_comps;
     pp_topology_functor ppf topo sorted connections);
  pf ppf "@]@."

(** Collect topologies from a translation unit. *)
let collect_topologies tu =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Mod_def_topology t -> Some t
      | Ast.Mod_def_module m ->
          List.find_map
            (fun ann2 ->
              match (Ast.unannotate ann2).Ast.data with
              | Ast.Mod_def_topology t -> Some t
              | _ -> None)
            m.Ast.module_members
      | _ -> None)
    tu.Ast.tu_members

(** Emit module types for leaf components in annotated topologies. The module
    type is generated from the component's input ports. *)
let pp_module_types tu ppf =
  let seen = Hashtbl.create 8 in
  let comps = ref [] in
  (* Collect leaf components from all annotated topologies. *)
  let topos = collect_topologies tu in
  List.iter
    (fun (topo : Ast.def_topology) ->
      let resolved = resolve_topology_instances tu topo in
      let connections = collect_direct_connections topo in
      let sorted = topo_sort_instances resolved connections in
      if is_functor_mode sorted connections then
        List.iter
          (fun (inst_name, _ci, (comp : Ast.def_component)) ->
            if comp.comp_kind <> Passive then
              let targets =
                target_instances inst_name comp connections sorted
              in
              if targets = [] && not (Hashtbl.mem seen comp.comp_name.data) then (
                Hashtbl.add seen comp.comp_name.data ();
                comps := comp :: !comps))
          sorted)
    topos;
  let comps = List.rev !comps in
  if comps <> [] then (
    pf ppf "@[<v>(* Module types generated by ofpp to-ml *)";
    List.iter (pp_port_module_type ppf tu) comps;
    pf ppf "@]@.@.")

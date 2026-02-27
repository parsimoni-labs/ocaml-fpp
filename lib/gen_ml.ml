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

let ocaml_type_of_fpp_type ?(type_env = []) (tn : Ast.type_name) =
  match tn with
  | Type_bool -> "bool"
  | Type_int (I8 | I16 | U8 | U16) -> "int"
  | Type_int (I32 | U32) -> "int32"
  | Type_int (I64 | U64) -> "int64"
  | Type_float (F32 | F64) -> "float"
  | Type_string _ -> "string"
  | Type_qual qi -> (
      let name = Ast.qual_ident_to_string qi.data in
      match List.assoc_opt name type_env with
      | Some t -> t
      | None -> (
          let parts = List.map Ast.unnode (Ast.qual_ident_to_list qi.data) in
          match List.rev parts with
          | [] -> "unit"
          | [ single ] -> camel_to_snake single
          | last :: prefix ->
              let modules = List.rev_map constructor_name prefix in
              String.concat "." (modules @ [ camel_to_snake last ])))

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
    (* Find the parent that contains this state.
       Exclude [st] itself so that name-shadowed states (parent and child
       sharing the same name) do not loop. *)
    let parent =
      List.find_opt
        (fun (p : Ast.def_state) ->
          p != st
          && List.exists
               (fun (s : Ast.def_state) ->
                 s.state_name.data = st.state_name.data)
               (Check_env.collect_substates p))
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
          p != st
          && List.exists
               (fun (s : Ast.def_state) ->
                 s.state_name.data = st.state_name.data)
               (Check_env.collect_substates p))
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

(** Whether a choice references any typed action or guard (needs a value
    parameter so the signal payload can be forwarded). *)
let choice_needs_value ~action_types ~guard_types (c : Ast.def_choice) =
  List.exists
    (fun cm ->
      let guard_typed =
        match cm with
        | Ast.Choice_if (Some g, _) -> (
            match List.assoc_opt g.data guard_types with
            | Some true -> true
            | _ -> false)
        | _ -> false
      in
      let acts =
        match cm with
        | Ast.Choice_if (_, te) -> te.data.trans_actions
        | Ast.Choice_else te -> te.data.trans_actions
      in
      let act_typed =
        List.exists
          (fun (act : Ast.ident Ast.node) ->
            match List.assoc_opt act.data action_types with
            | Some true -> true
            | _ -> false)
          acts
      in
      guard_typed || act_typed)
    c.choice_members

let rec pp_choice_fn ppf all_states all_choices ~action_types ~guard_types
    ~has_ctx ~needs_rec ~first (c : Ast.def_choice) =
  let name = camel_to_snake c.choice_name.data in
  let keyword =
    if !first then (
      first := false;
      if needs_rec then "let rec" else "let")
    else "and"
  in
  let needs_val = choice_needs_value ~action_types ~guard_types c in
  if needs_val then pf ppf "@,@,  %s enter_%s t v =" keyword name
  else pf ppf "@,@,  %s enter_%s t =" keyword name;
  let sig_var = if needs_val then Some "v" else None in
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
                pf ppf "@,    if G.%s t.ctx v then (" (camel_to_snake g.data)
              else pf ppf "@,    if G.%s t.ctx then (" (camel_to_snake g.data)
          | None -> pf ppf "@,    (");
          pp_choice_body ppf all_states all_choices ~action_types ~guard_types
            ~has_ctx ~sig_var acts tgt;
          pf ppf ")"
      | Ast.Choice_else te ->
          let tgt = target_name te.data.trans_target in
          let acts = te.data.trans_actions in
          pf ppf "@,    else (";
          pp_choice_body ppf all_states all_choices ~action_types ~guard_types
            ~has_ctx ~sig_var acts tgt;
          pf ppf ")")
    c.choice_members

and pp_enter_target ppf all_states all_choices ~action_types ~guard_types
    ~has_ctx ~sig_var ~indent tgt =
  match resolve_target all_states all_choices tgt with
  | Choice c ->
      let needs_val =
        match
          List.find_opt
            (fun (ch : Ast.def_choice) -> ch.choice_name.data = c)
            all_choices
        with
        | Some ch -> choice_needs_value ~action_types ~guard_types ch
        | None -> false
      in
      if needs_val then
        let v = match sig_var with Some v -> v | None -> "(* TODO *)" in
        pf ppf "@,%senter_%s t %s" indent (camel_to_snake c) v
      else pf ppf "@,%senter_%s t" indent (camel_to_snake c)
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
          if has_type then
            let v =
              match sig_var with Some v -> v | None -> "(* TODO: value *)"
            in
            pf ppf "@,%sA.%s t.ctx %s;" indent n v
          else pf ppf "@,%sA.%s t.ctx;" indent n)
        entry_acts;
      let ctor = constructor_name leaf in
      if has_ctx then pf ppf "@,%s{ t with state = State %s }" indent ctor
      else pf ppf "@,%s{ state = State %s }" indent ctor

and pp_choice_body ppf all_states all_choices ~action_types ~guard_types
    ~has_ctx ~sig_var acts tgt =
  List.iter
    (fun (act : Ast.ident Ast.node) ->
      let has_type =
        match List.assoc_opt act.data action_types with
        | Some true -> true
        | _ -> false
      in
      let name = camel_to_snake act.data in
      if has_type then
        let v = match sig_var with Some v -> v | None -> "(* TODO *)" in
        pf ppf "@,      A.%s t.ctx %s;" name v
      else pf ppf "@,      A.%s t.ctx;" name)
    acts;
  pp_enter_target ppf all_states all_choices ~action_types ~guard_types ~has_ctx
    ~sig_var ~indent:"      " tgt

(* ── Action list helper ───────────────────────────────────────────── *)

let pp_action_list ppf ~action_types ~sig_var ~indent acts =
  List.iter
    (fun (act : Ast.ident Ast.node) ->
      let n = camel_to_snake act.data in
      match List.assoc_opt act.data action_types with
      | Some true ->
          let v =
            match sig_var with Some v -> v | None -> "(* TODO: value *)"
          in
          pf ppf "@,%sA.%s t.ctx %s;" indent n v
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
        let sig_var =
          match s.signal_type with
          | None -> None
          | Some _ -> Some (sanitize_ident s.signal_name.data)
        in
        let sig_pat =
          match sig_var with
          | None -> sig_ctor
          | Some v -> Fmt.str "%s %s" sig_ctor v
        in
        pf ppf "@,    | State %s, %s ->" leaf_ctor sig_pat;
        pp_action_list ppf ~action_types ~sig_var ~indent:"        " exit_acts;
        let guarded =
          List.filter (fun tr -> Option.is_some tr.Ast.st_guard) matching
        in
        let unguarded =
          List.filter (fun tr -> Option.is_none tr.Ast.st_guard) matching
        in
        if guarded <> [] then
          pp_guarded ppf all_states all_choices ~action_types ~guard_types
            ~has_ctx ~sig_var guarded unguarded
        else
          match unguarded with
          | [ tr ] ->
              pp_transition ppf all_states all_choices ~action_types
                ~guard_types ~has_ctx ~sig_var tr
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
    ~sig_var guarded unguarded =
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
        let v =
          match sig_var with Some v -> v | None -> "(* TODO: value *)"
        in
        pf ppf "@,        %s G.%s t.ctx %s then begin" kw
          (camel_to_snake g.data) v
      else
        pf ppf "@,        %s G.%s t.ctx then begin" kw (camel_to_snake g.data);
      pp_transition ppf all_states all_choices ~action_types ~guard_types
        ~has_ctx ~sig_var tr;
      pf ppf "@,        end")
    guarded;
  match unguarded with
  | [ tr ] ->
      pf ppf "@,        else begin";
      pp_transition ppf all_states all_choices ~action_types ~guard_types
        ~has_ctx ~sig_var tr;
      pf ppf "@,        end"
  | _ -> pf ppf "@,        else t"

and pp_transition ppf all_states all_choices ~action_types ~guard_types ~has_ctx
    ~sig_var (tr : Ast.spec_state_transition) =
  match tr.st_action with
  | Ast.Transition te ->
      let tgt = target_name te.data.trans_target in
      pp_action_list ppf ~action_types ~sig_var ~indent:"        "
        te.data.trans_actions;
      pp_enter_target ppf all_states all_choices ~action_types ~guard_types
        ~has_ctx ~sig_var ~indent:"        " tgt
  | Ast.Do acts ->
      pp_action_list ppf ~action_types ~sig_var ~indent:"        " acts;
      pf ppf "@,        t"

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
      let entry_acts =
        match
          List.find_opt
            (fun (st : Ast.def_state) -> st.state_name.data = leaf)
            all_states
        with
        | Some st -> entry_actions_for_leaf st all_states
        | None -> []
      in
      pp_init_actions ppf ~action_types (all_acts @ entry_acts);
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

type ocaml_annots = {
  functor_path : string option;
  module_path : string option;
}

let starts_with ~prefix s =
  let plen = String.length prefix in
  String.length s >= plen && String.sub s 0 plen = prefix

let parse_ocaml_annotations annots =
  List.fold_left
    (fun acc s ->
      let s = String.trim s in
      if starts_with ~prefix:"ocaml.functor " s then
        let v = String.trim (String.sub s 14 (String.length s - 14)) in
        let path =
          match String.index_opt v '(' with
          | None -> v
          | Some i -> String.sub v 0 i
        in
        { acc with functor_path = Some path }
      else if starts_with ~prefix:"ocaml.module " s then
        let v = String.trim (String.sub s 13 (String.length s - 13)) in
        { acc with module_path = Some v }
      else acc)
    { functor_path = None; module_path = None }
    annots

(** Extract pre-annotations for a component definition from tu_members. For
    qualified identifiers (e.g. [Cohttp_mirage.Server]), searches within the
    named module. For unqualified names, searches top-level first. *)
let component_annots tu comp_qi =
  let find_in members name =
    List.find_map
      (fun ((pre, node, _) : Ast.module_member Ast.node Ast.annotated) ->
        match node.Ast.data with
        | Ast.Mod_def_component c when c.comp_name.data = name -> Some pre
        | _ -> None)
      members
  in
  let result =
    match comp_qi with
    | Ast.Qualified _ ->
        let parts = Ast.qual_ident_to_list comp_qi in
        let comp_name = (List.nth parts (List.length parts - 1)).data in
        let mod_parts =
          List.filteri (fun i _ -> i < List.length parts - 1) parts
        in
        let rec search_in members path =
          match path with
          | [] -> find_in members comp_name
          | (m : _ Ast.node) :: rest ->
              List.find_map
                (fun ((_, node, _) : Ast.module_member Ast.node Ast.annotated)
                   ->
                  match node.Ast.data with
                  | Ast.Mod_def_module md when md.Ast.module_name.data = m.data
                    ->
                      search_in md.Ast.module_members rest
                  | _ -> None)
                members
        in
        search_in tu.Ast.tu_members mod_parts
    | Ast.Unqualified id ->
        let name = id.data in
        let top = find_in tu.Ast.tu_members name in
        if Option.is_some top then top
        else
          List.find_map
            (fun ((_, node, _) : Ast.module_member Ast.node Ast.annotated) ->
              match node.Ast.data with
              | Ast.Mod_def_module m -> find_in m.Ast.module_members name
              | _ -> None)
            tu.Ast.tu_members
  in
  Option.value ~default:[] result

(** Collect a type environment from abstract type definitions in the translation
    unit. Each [type Foo] becomes [("Foo", "Foo.t")] by default. An
    [@ ocaml.type Path.t] annotation overrides the OCaml type. *)
let collect_type_env tu =
  let env = ref [] in
  let process (pre, (node : Ast.module_member Ast.node), _) =
    match node.Ast.data with
    | Ast.Mod_def_abs_type at ->
        let ocaml_type =
          List.find_map
            (fun s ->
              let s = String.trim s in
              if starts_with ~prefix:"ocaml.type " s then
                Some (String.trim (String.sub s 11 (String.length s - 11)))
              else None)
            pre
        in
        let t =
          match ocaml_type with Some t -> t | None -> at.abs_name.data ^ ".t"
        in
        env := (at.abs_name.data, t) :: !env
    | _ -> ()
  in
  List.iter process tu.Ast.tu_members;
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Mod_def_module m -> List.iter process m.Ast.module_members
      | _ -> ())
    tu.Ast.tu_members;
  List.rev !env

(** Extract (instance_name, pre_annotations) pairs from a topology. *)
let instance_annotations (topo : Ast.def_topology) =
  List.filter_map
    (fun ((pre, node, _) : Ast.topology_member Ast.node Ast.annotated) ->
      match node.Ast.data with
      | Ast.Topo_spec_comp_instance ci ->
          let inst_name =
            match ci.ci_instance.data with
            | Ast.Unqualified id -> id.data
            | Ast.Qualified _ -> Ast.qual_ident_to_string ci.ci_instance.data
          in
          Some (inst_name, pre)
      | _ -> None)
    topo.topo_members

(** Find [@ ocaml.module X] on an instance. When the same instance appears more
    than once (e.g. from import then redeclared in parent), the LAST entry wins,
    letting a parent topology override the imported binding. *)
let instance_bound_module inst_annots inst_name =
  let extract annots =
    List.find_map
      (fun s ->
        let s = String.trim s in
        if starts_with ~prefix:"ocaml.module " s then
          Some (String.trim (String.sub s 13 (String.length s - 13)))
        else None)
      annots
  in
  List.fold_left
    (fun acc (n, annots) ->
      if n = inst_name then
        match extract annots with Some _ as v -> v | None -> acc
      else acc)
    None inst_annots

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

(** Resolve a component qualified identifier to its definition. For qualified
    names (e.g. [Cohttp_mirage.Server]), searches within the named module. For
    unqualified names, searches top-level components first, then nested ones. *)
let resolve_component tu comp_qi =
  match comp_qi with
  | Ast.Qualified _ ->
      let parts = Ast.qual_ident_to_list comp_qi in
      let comp_name = (List.nth parts (List.length parts - 1)).data in
      let mod_parts =
        List.filteri (fun i _ -> i < List.length parts - 1) parts
      in
      let mod_names = List.map (fun (n : _ Ast.node) -> n.data) mod_parts in
      let rec search_in members path =
        match path with
        | [] ->
            List.find_map
              (fun ann ->
                match (Ast.unannotate ann).Ast.data with
                | Ast.Mod_def_component c when c.comp_name.data = comp_name ->
                    Some c
                | _ -> None)
              members
        | m :: rest ->
            List.find_map
              (fun ann ->
                match (Ast.unannotate ann).Ast.data with
                | Ast.Mod_def_module md when md.Ast.module_name.data = m ->
                    search_in md.Ast.module_members rest
                | _ -> None)
              members
      in
      search_in tu.Ast.tu_members mod_names
  | Ast.Unqualified id ->
      let name = id.data in
      let top_level =
        List.find_map
          (fun ann ->
            match (Ast.unannotate ann).Ast.data with
            | Ast.Mod_def_component c when c.comp_name.data = name -> Some c
            | _ -> None)
          tu.Ast.tu_members
      in
      if Option.is_some top_level then top_level
      else
        List.find_map
          (fun ann ->
            match (Ast.unannotate ann).Ast.data with
            | Ast.Mod_def_module m ->
                List.find_map
                  (fun ann2 ->
                    match (Ast.unannotate ann2).Ast.data with
                    | Ast.Mod_def_component c when c.comp_name.data = name ->
                        Some c
                    | _ -> None)
                  m.Ast.module_members
            | _ -> None)
          tu.Ast.tu_members

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
let port_type_parts ~type_env (port_def : Ast.def_port) =
  let params =
    List.map
      (fun ann ->
        let (fp : Ast.formal_param) = (Ast.unannotate ann).Ast.data in
        ocaml_type_of_fpp_type ~type_env fp.fp_type.data)
      port_def.port_params
  in
  let ret =
    match port_def.port_return with
    | Some tn -> ocaml_type_of_fpp_type ~type_env tn.data
    | None -> "unit"
  in
  (params, ret)

(** Pretty-print a module type generated from a component's input ports. For
    each [sync input port name: PortType], generates
    [val name : t -> param_types -> return_type]. *)
let pp_port_module_type ppf tu ~type_env (comp : Ast.def_component) =
  let name = String.uppercase_ascii (camel_to_snake comp.comp_name.data) in
  pf ppf "@,@,module type %s = sig" name;
  pf ppf "@,  type t";
  (* Emit component abstract types *)
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_def_abs_type at ->
          pf ppf "@,  type %s" (camel_to_snake at.abs_name.data)
      | _ -> ())
    comp.comp_members;
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
              let param_types, ret = port_type_parts ~type_env port_def in
              pf ppf "@,  val %s : t" port_name;
              List.iter (fun t -> pf ppf " -> %s" t) param_types;
              pf ppf " -> %s" ret
          | None -> pf ppf "@,  val %s : t -> unit" port_name)
      | None -> pf ppf "@,  val %s : t -> unit" port_name)
    input_ports;
  pf ppf "@,end"

(* ── Topology resolution ─────────────────────────────────────────── *)

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

(** Instance name for a topology member, or [None] for non-instance members. *)
let topo_member_inst_name ann =
  match (Ast.unannotate ann).Ast.data with
  | Ast.Topo_spec_comp_instance ci -> (
      match ci.ci_instance.data with
      | Ast.Unqualified id -> Some id.data
      | Ast.Qualified _ -> Some (Ast.qual_ident_to_string ci.ci_instance.data))
  | _ -> None

(** Flatten a topology by resolving [import] directives recursively. Public
    instances and connections from imported topologies are merged into the
    result. When a parent redeclares an imported instance (e.g. to override
    annotations), the imported entry is dropped. *)
let rec flatten_topology tu (topo : Ast.def_topology) =
  let members =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Topo_spec_top_import qi -> (
            let name =
              match qi.data with
              | Ast.Unqualified id -> id.data
              | Ast.Qualified _ -> Ast.qual_ident_to_string qi.data
            in
            let topos = collect_topologies tu in
            match
              List.find_opt (fun t -> t.Ast.topo_name.data = name) topos
            with
            | Some imported ->
                let flat = flatten_topology tu imported in
                List.filter
                  (fun ann2 ->
                    match (Ast.unannotate ann2).Ast.data with
                    | Ast.Topo_spec_comp_instance ci ->
                        ci.ci_visibility = `Public
                    | _ -> true)
                  flat.Ast.topo_members
            | None -> [])
        | _ -> [ ann ])
      topo.Ast.topo_members
  in
  (* Deduplicate: when an instance appears more than once, keep the last
     occurrence so parent redeclarations override imported entries. *)
  let seen = Hashtbl.create 8 in
  let members = List.rev members in
  let members =
    List.filter
      (fun ann ->
        match topo_member_inst_name ann with
        | None -> true
        | Some n ->
            if Hashtbl.mem seen n then false
            else (
              Hashtbl.add seen n ();
              true))
      members
  in
  let members = List.rev members in
  { topo with Ast.topo_members = members }

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

(** Collect direct connections from a topology, grouped by graph name. Groups
    with the same name (e.g. from imported sub-topologies) are merged. *)
let collect_direct_connections (topo : Ast.def_topology) =
  let raw =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Topo_spec_connection_graph
            (Ast.Graph_direct { graph_name; graph_connections }) ->
            let name = camel_to_snake graph_name.data in
            let conns =
              List.map
                (fun conn_ann -> (Ast.unannotate conn_ann).Ast.data)
                graph_connections
            in
            Some (name, conns)
        | _ -> None)
      topo.topo_members
  in
  (* Merge groups with the same name, preserving first-seen order *)
  let merged = ref [] in
  List.iter
    (fun (name, conns) ->
      match List.assoc_opt name !merged with
      | Some existing ->
          merged :=
            List.map
              (fun (n, c) -> if n = name then (n, existing @ conns) else (n, c))
              !merged
      | None -> merged := !merged @ [ (name, conns) ])
    raw;
  !merged

(** Merge all connection groups into a flat list. *)
let all_connections groups = List.concat_map snd groups

(** Extract instance name from a port instance identifier. *)
let pid_inst_name (pid : Ast.port_instance_id) =
  match pid.pid_component.data with
  | Ast.Unqualified id -> id.data
  | Ast.Qualified _ -> Ast.qual_ident_to_string pid.pid_component.data

(** Filter sorted instances to those referenced in a set of connections. *)
let group_instances sorted connections =
  let mentioned =
    List.concat_map
      (fun (conn : Ast.connection) ->
        [
          pid_inst_name conn.conn_from_port.data;
          pid_inst_name conn.conn_to_port.data;
        ])
      connections
  in
  List.filter (fun (n, _, _) -> List.mem n mentioned) sorted

(** Instances not mentioned in any connection group. These are included in the
    first group to preserve backward compatibility. *)
let orphan_instances sorted groups =
  let all_mentioned =
    List.concat_map
      (fun (_, conns) ->
        List.concat_map
          (fun (conn : Ast.connection) ->
            [
              pid_inst_name conn.conn_from_port.data;
              pid_inst_name conn.conn_to_port.data;
            ])
          conns)
      groups
  in
  List.filter (fun (n, _, _) -> not (List.mem n all_mentioned)) sorted

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
  let add_target (conn : Ast.connection) =
    let to_inst = pid_inst_name conn.conn_to_port.data in
    if not (Hashtbl.mem seen to_inst) then (
      Hashtbl.add seen to_inst ();
      match List.find_opt (fun (n, _, _) -> n = to_inst) sorted with
      | Some (_, _, target_comp) ->
          targets := (to_inst, target_comp) :: !targets
      | None -> ())
  in
  List.iter
    (fun (outp : Ast.port_instance_general) ->
      let port_name = camel_to_snake outp.gen_name.data in
      List.iter add_target (conns_from inst_name port_name connections))
    outputs;
  List.rev !targets

(** Pretty-print the connect function body. Leaf instances (no outgoing
    connections) become parameters; non-leaf instances are bound via their
    [connect] function.

    {b Lwt heuristic.} When any instance in [sorted] is an active component, the
    connect body opens [Lwt.Syntax], uses [let*] for active connect calls (plain
    [let] for passive ones), and wraps the return value in [Lwt.return]. A
    topology containing only passive components emits a plain synchronous record
    — no Lwt at all. *)
let pp_topo_connect_body ppf ~func_name group_sorted connections =
  let has_active =
    List.exists
      (fun (_, _, (comp : Ast.def_component)) -> is_active_component comp)
      group_sorted
  in
  (* Leaf instances (no outgoing connections) become function parameters;
     non-leaf instances are bound via their [connect] call. *)
  let leaf_params =
    List.filter_map
      (fun (inst_name, _ci, (comp : Ast.def_component)) ->
        if target_instances inst_name comp connections group_sorted = [] then
          Some (sanitize_ident inst_name)
        else None)
      group_sorted
  in
  let params =
    match leaf_params with [] -> "()" | _ -> String.concat " " leaf_params
  in
  if has_active then (
    pf ppf "@,  let %s %s =" func_name params;
    pf ppf "@,    let open Lwt.Syntax in")
  else pf ppf "@,  let %s %s =" func_name params;
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp connections group_sorted in
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
    group_sorted;
  if group_sorted = [] then pf ppf "@,    ()"
  else
    let fields =
      List.map (fun (inst_name, _, _) -> sanitize_ident inst_name) group_sorted
    in
    if has_active then
      pf ppf "@,    Lwt.return { %s }" (String.concat "; " fields)
    else pf ppf "@,    { %s }" (String.concat "; " fields)

(** Pretty-print a topology functor. Each instance becomes a module parameter.
    Leaf instances (no outgoing connections) use their named module type
    directly. Non-leaf instances carry an inline [val connect] whose arguments
    are the dependency instances. *)
let pp_functor_param ppf all_conns sorted inst_name (comp : Ast.def_component) =
  let mod_name = constructor_name inst_name in
  let comp_type = String.uppercase_ascii (camel_to_snake comp.comp_name.data) in
  let targets = target_instances inst_name comp all_conns sorted in
  if targets = [] then
    pf ppf "@,  (%s : sig include %s val connect : unit -> t end)" mod_name
      comp_type
  else
    let connect_ret = if is_active_component comp then "t Lwt.t" else "t" in
    pf ppf "@,  (%s : sig include %s val connect :" mod_name comp_type;
    List.iter
      (fun (target_inst, _) -> pf ppf " %s.t ->" (constructor_name target_inst))
      targets;
    pf ppf " %s end)" connect_ret

let pp_pattern_connections ppf topo =
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
    pf ppf " *)")

let pp_topology_functor ppf topo sorted groups =
  let all_conns = all_connections groups in
  let multi = List.length groups > 1 in
  let orphans = orphan_instances sorted groups in
  pf ppf "@,@,module Make";
  List.iter
    (fun (inst_name, _ci, comp) ->
      pp_functor_param ppf all_conns sorted inst_name comp)
    sorted;
  pf ppf " = struct";
  if groups = [] then (
    pf ppf "@,  type t = unit";
    pp_topo_connect_body ppf ~func_name:"connect" [] [])
  else
    List.iteri
      (fun i (name, conns) ->
        let gs = group_instances sorted conns in
        let gs = if i = 0 then gs @ orphans else gs in
        let type_name = if multi then name else "t" in
        if gs = [] then pf ppf "@,  type %s = unit" type_name
        else (
          pf ppf "@,  type %s = {" type_name;
          List.iter
            (fun (inst_name, _ci, _comp) ->
              pf ppf " %s : %s.t;" (sanitize_ident inst_name)
                (constructor_name inst_name))
            gs;
          pf ppf " }");
        pp_topo_connect_body ppf ~func_name:name gs conns)
      groups;
  pp_pattern_connections ppf topo;
  pf ppf "@,end"

(* ── Annotated (functor-application) topology mode ───────────────── *)

(** Whether a port is a dependency-only marker ([port Dep]). Dep ports model
    functor arguments in the connection graph but should not surface as labeled
    connect parameters. *)
let is_dep_port (p : Ast.port_instance_general) =
  match p.gen_port with
  | Some qi -> (
      match qi.data with Ast.Unqualified id -> id.data = "Dep" | _ -> false)
  | None -> true (* typeless ports are dependency-only *)

(** Input ports on [comp] that have no incoming connection for [inst_name].
    These surface as labeled parameters of the generated [connect] function.
    Dependency-only ports ([Dep]) are excluded — they model functor arguments,
    not connect parameters. *)
let unconnected_input_ports inst_name (comp : Ast.def_component) connections =
  let input_ports =
    List.filter_map
      (fun (_pre, (p : Ast.port_instance_general)) ->
        if p.gen_kind <> Output && not (is_dep_port p) then Some p else None)
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
    input_ports

(** Emit functor applications for non-leaf instances inside the Make struct.
    Bound instances (with [@ ocaml.module]) are skipped — they already have
    module aliases. *)
let pp_functor_apps ppf tu inst_annots sorted connections =
  List.iter
    (fun (inst_name, ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp connections sorted in
      if targets <> [] && instance_bound_module inst_annots inst_name = None
      then
        let mod_name = constructor_name inst_name in
        let ca =
          parse_ocaml_annotations
            (component_annots tu ci.Ast.inst_component.data)
        in
        match ca.module_path with
        | Some path ->
            (* Concrete module alias — no functor application *)
            pf ppf "@,  module %s = %s" mod_name path
        | None ->
            let functor_path =
              match ca.functor_path with
              | Some s -> s
              | None ->
                  let parts =
                    Ast.qual_ident_to_list ci.Ast.inst_component.data
                  in
                  let segments =
                    List.map (fun n -> constructor_name n.Ast.data) parts
                  in
                  String.concat "." segments ^ ".Make"
            in
            pf ppf "@,  module %s = %s" mod_name functor_path;
            List.iter
              (fun (target_inst, _) ->
                pf ppf "(%s)" (constructor_name target_inst))
              targets)
    sorted

(** Emit individual connect calls for non-leaf, non-passive instances. Passive
    (module-only) components get functor applications but no connect. *)
let pp_one_connect_call ppf inst_name comp connections group_sorted =
  let targets = target_instances inst_name comp connections group_sorted in
  if targets = [] then ()
  else
    let inst_var = sanitize_ident inst_name in
    let mod_name = constructor_name inst_name in
    let bind = if is_active_component comp then "let* " else "let " in
    let config_ports = unconnected_input_ports inst_name comp connections in
    pf ppf "@,    %s%s = %s.connect" bind inst_var mod_name;
    List.iter
      (fun (p : Ast.port_instance_general) ->
        pf ppf " ~%s" (sanitize_ident p.gen_name.data))
      config_ports;
    List.iter
      (fun (target_inst, (tc : Ast.def_component)) ->
        if tc.comp_kind <> Passive then
          pf ppf " %s" (sanitize_ident target_inst))
      targets;
    pf ppf " in"

let pp_annotated_connect_calls ppf _tu group_sorted connections =
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      if comp.comp_kind <> Passive then
        pp_one_connect_call ppf inst_name comp connections group_sorted)
    group_sorted

(** Emit the connect function for annotated topology mode. Passive (module-only)
    components are excluded from the connect body, record fields, and functor
    parameters. Bound leaves (with [@ ocaml.module]) are auto-initialised.

    {b Lwt heuristic.} The connect function is asynchronous ([Lwt.Syntax],
    [let*], [Lwt.return]) when at least one concrete (non-passive) active
    component either has outgoing connections (non-leaf) or is bound to a
    concrete module. A passive component with a functor application (e.g.
    [Crunch.Make]) contributes a [module] binding but no [connect] call, so it
    does not trigger Lwt. This means a topology whose only non-passive leaf is
    an unbound functor parameter emits a synchronous connect — the parameter's
    [connect] is called by the consumer, not by us. *)
let pp_bound_leaf_inits ppf inst_annots concrete connections group_sorted =
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp connections group_sorted in
      if targets = [] then
        match instance_bound_module inst_annots inst_name with
        | Some _ ->
            let bind = if is_active_component comp then "let* " else "let " in
            pf ppf "@,    %s%s = %s.connect () in" bind
              (sanitize_ident inst_name)
              (constructor_name inst_name)
        | None -> ())
    concrete

let pp_connect_return ppf ~has_active concrete =
  if concrete = [] then
    if has_active then pf ppf "@,    Lwt.return ()" else pf ppf "@,    ()"
  else
    let fields =
      List.map (fun (inst_name, _, _) -> sanitize_ident inst_name) concrete
    in
    if has_active then
      pf ppf "@,    Lwt.return { %s }" (String.concat "; " fields)
    else pf ppf "@,    { %s }" (String.concat "; " fields)

let pp_annotated_connect ppf tu ~func_name inst_annots group_sorted connections
    =
  let concrete =
    List.filter
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      group_sorted
  in
  let has_active =
    List.exists
      (fun (inst_name, _ci, (comp : Ast.def_component)) ->
        let targets =
          target_instances inst_name comp connections group_sorted
        in
        is_active_component comp
        && (targets <> [] || instance_bound_module inst_annots inst_name <> None))
      concrete
  in
  let labeled_args =
    List.concat_map
      (fun (inst_name, _ci, (comp : Ast.def_component)) ->
        if target_instances inst_name comp connections group_sorted <> [] then
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
        if
          target_instances inst_name comp connections group_sorted = []
          && instance_bound_module inst_annots inst_name = None
        then Some (sanitize_ident inst_name)
        else None)
      concrete
  in
  pf ppf "@,@,  let %s" func_name;
  List.iter (fun arg -> pf ppf " ~%s" arg) labeled_args;
  List.iter (fun p -> pf ppf " %s" p) leaf_params;
  if labeled_args = [] && leaf_params = [] then pf ppf " ()";
  pf ppf " =";
  if has_active then pf ppf "@,    let open Lwt.Syntax in";
  pp_bound_leaf_inits ppf inst_annots concrete connections group_sorted;
  pp_annotated_connect_calls ppf tu group_sorted connections;
  pp_connect_return ppf ~has_active concrete

(** Pretty-print an annotated topology in functor-application mode. Passive
    components are module-only: they get functor applications but no record
    fields, connect calls, or Make parameters. Instances with [@ ocaml.module X]
    are bound to concrete modules and auto-initialised. *)
let pp_topology_annotated ppf tu topo sorted groups =
  let all_conns = all_connections groups in
  let multi = List.length groups > 1 in
  let orphans = orphan_instances sorted groups in
  let inst_annots = instance_annotations topo in
  let concrete =
    List.filter
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      sorted
  in
  pf ppf "@,@,module Make";
  (* Only emit functor params for unbound leaves *)
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp all_conns sorted in
      if targets = [] && instance_bound_module inst_annots inst_name = None then
        let mod_name = constructor_name inst_name in
        let constraint_ =
          String.uppercase_ascii (camel_to_snake comp.comp_name.data)
        in
        pf ppf "@,  (%s : %s)" mod_name constraint_)
    concrete;
  pf ppf " = struct";
  (* Emit module aliases for all bound instances *)
  List.iter
    (fun (inst_name, _ci, _comp) ->
      match instance_bound_module inst_annots inst_name with
      | Some concrete_mod ->
          pf ppf "@,  module %s = %s" (constructor_name inst_name) concrete_mod
      | None -> ())
    concrete;
  pp_functor_apps ppf tu inst_annots sorted all_conns;
  List.iteri
    (fun i (name, conns) ->
      let gs = group_instances sorted conns in
      let gs = if i = 0 then gs @ orphans else gs in
      let gc =
        List.filter
          (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
          gs
      in
      let type_name = if multi then name else "t" in
      if gc = [] then pf ppf "@,@,  type %s = unit" type_name
      else (
        pf ppf "@,@,  type %s = {" type_name;
        List.iter
          (fun (inst_name, _ci, _comp) ->
            let mod_name = constructor_name inst_name in
            pf ppf " %s : %s.t;" (sanitize_ident inst_name) mod_name)
          gc;
        pf ppf " }");
      pp_annotated_connect ppf tu ~func_name:name inst_annots gs conns)
    groups;
  pf ppf "@,end"

(* ── Fully-bound topology mode ────────────────────────────────────── *)

(** Emit a single top-level lazy binding for an active instance. Leaf instances
    (no deps) emit [let x = lazy (X.connect ())]. Non-leaf instances force
    active dependencies and pass non-passive values to [connect]. *)
let pp_lazy_binding ppf inst_name (comp : Ast.def_component) connections sorted
    =
  let inst_var = sanitize_ident inst_name in
  let mod_name = constructor_name inst_name in
  let targets = target_instances inst_name comp connections sorted in
  if targets = [] then pf ppf "let %s = lazy (%s.connect ())" inst_var mod_name
  else
    let active_targets =
      List.filter
        (fun (_, (tc : Ast.def_component)) -> tc.comp_kind <> Passive)
        targets
    in
    let config_ports = unconnected_input_ports inst_name comp connections in
    pf ppf "let %s = lazy (" inst_var;
    pf ppf "@,  let open Lwt.Syntax in";
    List.iter
      (fun (target_inst, _) ->
        pf ppf "@,  let* %s = Lazy.force %s in"
          (sanitize_ident target_inst)
          (sanitize_ident target_inst))
      active_targets;
    pf ppf "@,  %s.connect" mod_name;
    List.iter
      (fun (p : Ast.port_instance_general) ->
        pf ppf " ~%s" (sanitize_ident p.gen_name.data))
      config_ports;
    List.iter
      (fun (target_inst, (tc : Ast.def_component)) ->
        if tc.comp_kind <> Passive then
          pf ppf " %s" (sanitize_ident target_inst))
      targets;
    pf ppf ")"

(** Pretty-print a flat topology for fully-bound annotated mode. Module aliases
    and functor applications are at top level (no [Make] struct wrapper). Active
    instances get [lazy] bindings. *)
let pp_topology_flat ppf tu topo sorted groups =
  let all_conns = all_connections groups in
  let inst_annots = instance_annotations topo in
  let first_module = ref true in
  let module_break () =
    if !first_module then (
      pf ppf "@,";
      first_module := false);
    pf ppf "@,"
  in
  (* Phase 1: Module aliases for bound instances *)
  List.iter
    (fun (inst_name, _ci, _comp) ->
      match instance_bound_module inst_annots inst_name with
      | Some concrete_mod ->
          module_break ();
          pf ppf "module %s = %s" (constructor_name inst_name) concrete_mod
      | None -> ())
    sorted;
  (* Phase 2: Functor applications for non-leaf, non-bound instances *)
  List.iter
    (fun (inst_name, ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp all_conns sorted in
      if targets <> [] && instance_bound_module inst_annots inst_name = None
      then
        let mod_name = constructor_name inst_name in
        let ca =
          parse_ocaml_annotations
            (component_annots tu ci.Ast.inst_component.data)
        in
        match ca.module_path with
        | Some path ->
            module_break ();
            pf ppf "module %s = %s" mod_name path
        | None ->
            module_break ();
            let functor_path =
              match ca.functor_path with
              | Some s -> s
              | None ->
                  let parts =
                    Ast.qual_ident_to_list ci.Ast.inst_component.data
                  in
                  let segments =
                    List.map (fun n -> constructor_name n.Ast.data) parts
                  in
                  String.concat "." segments ^ ".Make"
            in
            pf ppf "module %s = %s" mod_name functor_path;
            List.iter
              (fun (target_inst, _) ->
                pf ppf "(%s)" (constructor_name target_inst))
              targets)
    sorted;
  (* Phase 3: Lazy bindings for active instances. All use [.connect]. *)
  let concrete =
    List.filter
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      sorted
  in
  ignore
    (List.fold_left
       (fun prev_leaf (inst_name, _ci, (comp : Ast.def_component)) ->
         let targets = target_instances inst_name comp all_conns sorted in
         let is_leaf = targets = [] in
         if prev_leaf && is_leaf then pf ppf "@," else pf ppf "@,@,";
         pp_lazy_binding ppf inst_name comp all_conns sorted;
         is_leaf)
       false concrete)

(** Whether a topology should use functor-application mode. Triggered when any
    component has an active non-leaf instance (the original rule) OR when any
    component carries an [@ ocaml.functor] or [@ ocaml.module] annotation. *)
let is_functor_mode tu sorted connections =
  List.exists
    (fun (inst_name, ci, (comp : Ast.def_component)) ->
      comp.comp_kind <> Passive
      && connection_targets inst_name connections <> []
      ||
      let ca =
        parse_ocaml_annotations (component_annots tu ci.Ast.inst_component.data)
      in
      Option.is_some ca.functor_path || Option.is_some ca.module_path)
    sorted

(** Whether a topology would produce OCaml code. In functor-application mode,
    topologies with no concrete (non-passive) instances are import-only
    sub-topologies and produce no output. Regular mode always produces output.
*)
let topology_has_output tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let connections = all_connections (collect_direct_connections topo) in
  let sorted = topo_sort_instances resolved connections in
  let has_concrete =
    List.exists
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      sorted
  in
  has_concrete || not (is_functor_mode tu sorted connections)

(** Internal: check fully-bound with pre-computed values. *)
let is_fully_bound inst_annots sorted connections =
  let concrete =
    List.filter
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      sorted
  in
  concrete <> []
  && not
       (List.exists
          (fun (inst_name, _ci, (comp : Ast.def_component)) ->
            let targets = target_instances inst_name comp connections sorted in
            targets = [] && instance_bound_module inst_annots inst_name = None)
          concrete)

let topology_is_fully_bound tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let inst_annots = instance_annotations topo in
  let resolved = resolve_topology_instances tu topo in
  let connections = all_connections (collect_direct_connections topo) in
  let sorted = topo_sort_instances resolved connections in
  is_fully_bound inst_annots sorted connections

(** Return connect function names for a topology (one per connection group). *)
let topology_connect_names tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let groups = collect_direct_connections topo in
  List.map fst groups

(** Pretty-print a full topology as OCaml code. In functor-application mode,
    topologies with no concrete (non-passive) instances are import-only
    sub-topologies and produce no output. Fully-bound annotated topologies use
    top-level lazy bindings (no [Make] struct wrapper). *)
let pp_topology tu ppf (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let groups = collect_direct_connections topo in
  let connections = all_connections groups in
  let sorted = topo_sort_instances resolved connections in
  if not (topology_has_output tu topo) then ()
  else begin
    pf ppf "@[<v>(* Generated by ofpp to-ml from topology %s *)"
      topo.topo_name.data;
    (let inst_annots = instance_annotations topo in
     if is_fully_bound inst_annots sorted connections then
       pp_topology_flat ppf tu topo sorted groups
     else if is_functor_mode tu sorted connections then
       pp_topology_annotated ppf tu topo sorted groups
     else
       let type_env = collect_type_env tu in
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
       List.iter
         (fun comp -> pp_port_module_type ppf tu ~type_env comp)
         unique_comps;
       pp_topology_functor ppf topo sorted groups);
    pf ppf "@]@."
  end

(** Emit module types for leaf components in annotated topologies. The module
    type is generated from the component's input ports. *)
let is_unseen_leaf_comp seen inst_annots connections sorted inst_name
    (comp : Ast.def_component) =
  comp.comp_kind <> Passive
  && target_instances inst_name comp connections sorted = []
  && instance_bound_module inst_annots inst_name = None
  && not (Hashtbl.mem seen comp.comp_name.data)

let collect_leaf_comps_from_topo tu seen comps (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let inst_annots = instance_annotations topo in
  let resolved = resolve_topology_instances tu topo in
  let connections = all_connections (collect_direct_connections topo) in
  let sorted = topo_sort_instances resolved connections in
  if is_functor_mode tu sorted connections then
    List.iter
      (fun (inst_name, _ci, comp) ->
        if
          is_unseen_leaf_comp seen inst_annots connections sorted inst_name comp
        then (
          Hashtbl.add seen comp.comp_name.data ();
          comps := comp :: !comps))
      sorted

let collect_leaf_comps tu topos =
  let seen = Hashtbl.create 8 in
  let comps = ref [] in
  List.iter (collect_leaf_comps_from_topo tu seen comps) topos;
  List.rev !comps

let has_module_types tu topos =
  let comps = collect_leaf_comps tu topos in
  comps <> []

let pp_module_types tu topos ppf =
  let comps = collect_leaf_comps tu topos in
  if comps <> [] then (
    let type_env = collect_type_env tu in
    pf ppf "@[<v>(* Module types generated by ofpp to-ml *)";
    List.iter (fun comp -> pp_port_module_type ppf tu ~type_env comp) comps;
    pf ppf "@]@.@.")

(** Emit a [let () = Lwt_main.run (...)] entry point. Each element is
    [(topo_module_name, func_name)] where [func_name] is a connection group
    name. Uses [@.] (print_newline) instead of [@,] because this is called
    outside any formatting box. *)
let pp_main_entry_multi ppf topos =
  let wrap = List.length topos > 1 in
  match topos with
  | [] -> ()
  | [ (_, func_name) ] ->
      pf ppf "let () =@.  Lwt_main.run (Make.%s () |> Lwt.map ignore)@."
        func_name
  | _ ->
      pf ppf "let () =@.  Lwt_main.run begin@.";
      pf ppf "    let open Lwt.Syntax in@.";
      List.iter
        (fun (topo_name, func_name) ->
          let var = camel_to_snake topo_name in
          let prefix = if wrap then topo_name ^ "." else "" in
          pf ppf "    let* _%s = %sMake.%s () in@." var prefix func_name)
        topos;
      pf ppf "    Lwt.return ()@.";
      pf ppf "  end@."

(* ── .mli generation ─────────────────────────────────────────────── *)

(** Pretty-print the .mli for a parameterised (simple functor) topology. Emits
    [module Make(...) : sig type t val connect : ... end]. *)
let pp_topology_functor_mli ppf topo sorted groups =
  let all_conns = all_connections groups in
  let multi = List.length groups > 1 in
  pf ppf "@,@,module Make";
  List.iter
    (fun (inst_name, _ci, comp) ->
      pp_functor_param ppf all_conns sorted inst_name comp)
    sorted;
  pf ppf " : sig";
  if groups = [] then (
    pf ppf "@,  type t = unit";
    pf ppf "@,  val connect : unit -> t Lwt.t")
  else
    List.iter
      (fun (name, conns) ->
        let gs = group_instances sorted conns in
        let type_name = if multi then name else "t" in
        if gs = [] then pf ppf "@,  type %s = unit" type_name
        else (
          pf ppf "@,  type %s = {" type_name;
          List.iter
            (fun (inst_name, _ci, _comp) ->
              pf ppf " %s : %s.t;" (sanitize_ident inst_name)
                (constructor_name inst_name))
            gs;
          pf ppf " }");
        let leaf_params =
          List.filter_map
            (fun (inst_name, _ci, (comp : Ast.def_component)) ->
              if target_instances inst_name comp conns gs = [] then
                Some (sanitize_ident inst_name, constructor_name inst_name)
              else None)
            gs
        in
        let has_active =
          List.exists
            (fun (_, _, (comp : Ast.def_component)) -> is_active_component comp)
            gs
        in
        let ret = if has_active then type_name ^ " Lwt.t" else type_name in
        pf ppf "@,  val %s :" name;
        List.iter (fun (_, m) -> pf ppf " %s.t ->" m) leaf_params;
        if leaf_params = [] then pf ppf " unit ->";
        pf ppf " %s" ret)
      groups;
  pp_pattern_connections ppf topo;
  pf ppf "@,end"

(** Pretty-print the .mli for an annotated (functor-application) topology. *)
let pp_topology_annotated_mli ppf _tu topo sorted groups =
  let all_conns = all_connections groups in
  let multi = List.length groups > 1 in
  let orphans = orphan_instances sorted groups in
  let inst_annots = instance_annotations topo in
  let concrete =
    List.filter
      (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
      sorted
  in
  pf ppf "@,@,module Make";
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      let targets = target_instances inst_name comp all_conns sorted in
      if targets = [] && instance_bound_module inst_annots inst_name = None then
        let mod_name = constructor_name inst_name in
        let constraint_ =
          String.uppercase_ascii (camel_to_snake comp.comp_name.data)
        in
        pf ppf "@,  (%s : %s)" mod_name constraint_)
    concrete;
  pf ppf " : sig";
  List.iteri
    (fun i (name, conns) ->
      let gs = group_instances sorted conns in
      let gs = if i = 0 then gs @ orphans else gs in
      let gc =
        List.filter
          (fun (_, _, (comp : Ast.def_component)) -> comp.comp_kind <> Passive)
          gs
      in
      let type_name = if multi then name else "t" in
      if gc = [] then pf ppf "@,  type %s = unit" type_name
      else (
        pf ppf "@,  type %s = {" type_name;
        List.iter
          (fun (inst_name, _ci, _comp) ->
            let mod_name = constructor_name inst_name in
            pf ppf " %s : %s.t;" (sanitize_ident inst_name) mod_name)
          gc;
        pf ppf " }");
      (* Connect signature *)
      let labeled_args =
        List.concat_map
          (fun (inst_name, _ci, (comp : Ast.def_component)) ->
            if target_instances inst_name comp conns gs <> [] then
              List.map
                (fun (p : Ast.port_instance_general) ->
                  sanitize_ident p.gen_name.data)
                (unconnected_input_ports inst_name comp all_conns)
            else [])
          concrete
      in
      let leaf_params =
        List.filter_map
          (fun (inst_name, _ci, (comp : Ast.def_component)) ->
            if
              target_instances inst_name comp conns gs = []
              && instance_bound_module inst_annots inst_name = None
            then Some (sanitize_ident inst_name, constructor_name inst_name)
            else None)
          concrete
      in
      let has_active =
        List.exists
          (fun (inst_name, _ci, (comp : Ast.def_component)) ->
            let targets = target_instances inst_name comp conns gs in
            is_active_component comp
            && (targets <> []
               || instance_bound_module inst_annots inst_name <> None))
          concrete
      in
      let ret = if has_active then type_name ^ " Lwt.t" else type_name in
      pf ppf "@,  val %s :" name;
      List.iter (fun arg -> pf ppf " %s:_ ->" arg) labeled_args;
      List.iter (fun (_, m) -> pf ppf " %s.t ->" m) leaf_params;
      if labeled_args = [] && leaf_params = [] then pf ppf " unit ->";
      pf ppf " %s" ret)
    groups;
  pf ppf "@,end"

(** Pretty-print the .mli for a flat (fully-bound) topology. Emits
    [module X = ...] and [val x : X.t Lazy.t]. *)
let pp_topology_flat_mli ppf tu topo sorted groups =
  let all_conns = all_connections groups in
  let inst_annots = instance_annotations topo in
  let first_module = ref true in
  List.iter
    (fun (inst_name, ci, (comp : Ast.def_component)) ->
      if comp.comp_kind <> Passive then begin
        let mod_name = constructor_name inst_name in
        let targets = target_instances inst_name comp all_conns sorted in
        if targets = [] then begin
          match instance_bound_module inst_annots inst_name with
          | Some concrete_mod ->
              if !first_module then (
                pf ppf "@,";
                first_module := false);
              pf ppf "@,module %s = %s" mod_name concrete_mod
          | None -> ()
        end
      end;
      ignore ci)
    sorted;
  pf ppf "@,";
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      if comp.comp_kind <> Passive then begin
        let inst_var = sanitize_ident inst_name in
        let mod_name = constructor_name inst_name in
        pf ppf "@,val %s : %s.t Lazy.t" inst_var mod_name
      end)
    sorted;
  ignore (tu, topo)

(** Pretty-print the .mli for a topology. Dispatches to the correct mode. *)
let pp_topology_mli tu ppf (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let groups = collect_direct_connections topo in
  let connections = all_connections groups in
  let sorted = topo_sort_instances resolved connections in
  if not (topology_has_output tu topo) then ()
  else begin
    pf ppf "@[<v>(** Generated by ofpp to-ml from topology %s. *)"
      topo.topo_name.data;
    (let inst_annots = instance_annotations topo in
     if is_fully_bound inst_annots sorted connections then
       pp_topology_flat_mli ppf tu topo sorted groups
     else if is_functor_mode tu sorted connections then
       pp_topology_annotated_mli ppf tu topo sorted groups
     else pp_topology_functor_mli ppf topo sorted groups);
    pf ppf "@]@."
  end

(** Return [(var_name, module_name)] pairs for active instances that get lazy
    bindings, in topo-sorted order. *)
let topology_active_instance_names tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let connections = all_connections (collect_direct_connections topo) in
  let sorted = topo_sort_instances resolved connections in
  List.filter_map
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      if comp.comp_kind <> Passive then
        Some (sanitize_ident inst_name, constructor_name inst_name)
      else None)
    sorted

(** Emit a [let () = Lwt_main.run (...)] entry point that forces each lazy
    binding with [let* _ = Lazy.force x in] and finishes with [Lwt.return ()].
    Each element of [names] is [(var_name, module_name)]. *)
let pp_flat_entry_point ppf names =
  match names with
  | [] -> ()
  | _ ->
      pf ppf "let () =@.  Lwt_main.run begin@.";
      pf ppf "    let open Lwt.Syntax in@.";
      List.iter
        (fun (var, _) -> pf ppf "    let* _ = Lazy.force %s in@." var)
        names;
      pf ppf "    Lwt.return ()@.";
      pf ppf "  end@."

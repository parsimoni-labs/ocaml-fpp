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

type ocaml_annots = { module_path : string option; sig_path : string option }

let starts_with ~prefix s =
  let plen = String.length prefix in
  String.length s >= plen && String.sub s 0 plen = prefix

let parse_ocaml_annotations annots =
  List.fold_left
    (fun acc s ->
      let s = String.trim s in
      if starts_with ~prefix:"ocaml.module " s then
        let v = String.trim (String.sub s 13 (String.length s - 13)) in
        { acc with module_path = Some v }
      else if starts_with ~prefix:"ocaml.sig " s then
        let v = String.trim (String.sub s 10 (String.length s - 10)) in
        { acc with sig_path = Some v }
      else acc)
    { module_path = None; sig_path = None }
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

(** Parse a single [ocaml.param name "value"] annotation string. *)
let parse_param_annotation s =
  let s = String.trim s in
  if starts_with ~prefix:"ocaml.param " s then
    let rest = String.trim (String.sub s 12 (String.length s - 12)) in
    match String.index_opt rest ' ' with
    | Some i ->
        let name = String.sub rest 0 i in
        let value =
          String.trim (String.sub rest (i + 1) (String.length rest - i - 1))
        in
        Some (name, value)
    | None -> None
  else None

(** Find [@ ocaml.param name "value"] annotations on an instance. Returns a
    mapping from param name to the OCaml literal string. Multiple annotations
    may override different params. *)
let instance_param_annotations inst_annots inst_name =
  let tbl = Hashtbl.create 4 in
  let annots =
    List.concat_map
      (fun (n, annots) -> if n = inst_name then annots else [])
      inst_annots
  in
  List.iter
    (fun s ->
      match parse_param_annotation s with
      | Some (name, value) -> Hashtbl.replace tbl name value
      | None -> ())
    annots;
  tbl

(** Extract instance name from a port instance identifier. *)
let pid_inst_name (pid : Ast.port_instance_id) =
  match pid.pid_component.data with
  | Ast.Unqualified id -> id.data
  | Ast.Qualified _ -> Ast.qual_ident_to_string pid.pid_component.data

(* ── Runtime component convention ─────────────────────────────────── *)

(** A component named [Runtime] (possibly nested in a module, e.g.
    [Stacks.Runtime]) is a runtime config provider. Its output ports model
    labeled keyword arguments injected into the [connect] call of target
    instances. Runtime instances produce no module alias, no functor
    application, and no lazy binding. *)
let is_runtime_component (comp : Ast.def_component) =
  comp.comp_name.data = "Runtime"

(** Whether a port on a Runtime component is annotated [@ ocaml.optional]. *)
let is_optional_runtime_port (comp : Ast.def_component) port_name =
  List.exists
    (fun ((pre, node, _) : Ast.component_member Ast.node Ast.annotated) ->
      match node.Ast.data with
      | Ast.Comp_spec_port_instance (Ast.Port_general p) ->
          camel_to_snake p.gen_name.data = port_name
          && List.exists (fun s -> String.trim s = "ocaml.optional") pre
      | _ -> false)
    comp.comp_members

(** Return the name of the first [sync input port] on a component, if any. Used
    as the default method name when an instance has no outgoing connections
    (e.g. a standalone application with [sync input port start]). *)
let sync_input_port_name (comp : Ast.def_component) =
  List.find_map
    (fun ((_pre, node, _post) : Ast.component_member Ast.node Ast.annotated) ->
      match node.Ast.data with
      | Ast.Comp_spec_port_instance (Ast.Port_general p)
        when p.gen_kind = Sync_input ->
          Some (camel_to_snake p.gen_name.data)
      | _ -> None)
    comp.comp_members

(** Extract [param] declarations from a component, in declaration order. Each
    param has a name, an FPP type, an optional default expression, a flag
    indicating whether it is positional ([@ ocaml.positional]), and a flag
    indicating whether it is optional ([@ ocaml.optional]). *)
let component_params (comp : Ast.def_component) =
  List.filter_map
    (fun ((pre, node, _post) : Ast.component_member Ast.node Ast.annotated) ->
      match node.Ast.data with
      | Ast.Comp_spec_param p ->
          let positional =
            List.exists (fun a -> String.trim a = "ocaml.positional") pre
          in
          let optional =
            List.exists (fun a -> String.trim a = "ocaml.optional") pre
          in
          Some (p, positional, optional)
      | _ -> None)
    comp.comp_members

(** Look up init spec overrides on a component instance. Phase [n] overrides
    param [n] (0-indexed). Returns a mapping from param index to the raw OCaml
    code string. *)
let init_spec_overrides (ci : Ast.def_component_instance) =
  let tbl = Hashtbl.create 4 in
  List.iter
    (fun ann ->
      let si : Ast.spec_init = (Ast.unannotate ann).Ast.data in
      match si.init_phase.data with
      | Ast.Expr_literal (Lit_int s) -> (
          match int_of_string_opt s with
          | Some n -> Hashtbl.replace tbl n si.init_code.data
          | None -> ())
      | _ -> ())
    ci.inst_init;
  tbl

(** Map an FPP type to its Cmdliner converter name. *)
let cmdliner_conv_of_fpp_type (tn : Ast.type_name) =
  match tn with
  | Type_bool -> "bool"
  | Type_int (I8 | I16 | U8 | U16) -> "int"
  | Type_int (I32 | U32 | I64 | U64) -> "int"
  | Type_float (F32 | F64) -> "float"
  | Type_string _ -> "string"
  | Type_qual _ -> "string"

(** Render an FPP default expression as an OCaml literal. *)
let rec ocaml_literal_of_expr (e : Ast.expr) =
  match e with
  | Expr_literal (Lit_string s) -> Fmt.str "%S" s
  | Expr_literal (Lit_int s) -> s
  | Expr_literal (Lit_float s) -> s
  | Expr_literal (Lit_bool b) -> string_of_bool b
  | Expr_paren e -> ocaml_literal_of_expr e.data
  | _ -> "()"

(** Collect runtime labelled arguments for a target instance: for each
    connection FROM a runtime instance TO [inst_name], return
    [(port_name, is_optional)]. The order follows the output port declaration
    order. *)
let runtime_labelled_args inst_name sorted connections =
  let raw =
    List.filter_map
      (fun (conn : Ast.connection) ->
        let to_inst = pid_inst_name conn.conn_to_port.data in
        if to_inst = inst_name then
          let from_inst = pid_inst_name conn.conn_from_port.data in
          match List.find_opt (fun (n, _, _) -> n = from_inst) sorted with
          | Some (_, _, comp) when is_runtime_component comp ->
              let port =
                camel_to_snake conn.conn_from_port.data.pid_port.data
              in
              let optional = is_optional_runtime_port comp port in
              Some (from_inst, (port, optional))
          | _ -> None
        else None)
      connections
  in
  List.map snd raw

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

(** Merge all connection groups into a single list. *)
let all_connections groups = List.concat_map snd groups

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

(** Filter a sorted instance list to exclude runtime components. *)
let filter_non_runtime sorted =
  List.filter (fun (_, _, comp) -> not (is_runtime_component comp)) sorted

(** Assign each non-runtime instance to its earliest connection group. Returns
    [(group_name, instances)] pairs in group order, with instances topo-sorted
    within each group. Standalone instances (no connections) go into a synthetic
    group named after their sync input port. Dependencies that would create a
    backward cross-group reference are pulled into the earlier group. *)
let partition_instances_by_group non_rt groups all_conns =
  let assigned = Hashtbl.create 16 in
  List.iter
    (fun (inst_name, _, (comp : Ast.def_component)) ->
      let earliest =
        List.find_map
          (fun (gname, conns) ->
            let appears =
              List.exists
                (fun (conn : Ast.connection) ->
                  pid_inst_name conn.conn_from_port.data = inst_name
                  || pid_inst_name conn.conn_to_port.data = inst_name)
                conns
            in
            if appears then Some gname else None)
          groups
      in
      match earliest with
      | Some g -> Hashtbl.replace assigned inst_name g
      | None ->
          let port =
            sync_input_port_name comp |> Option.value ~default:"connect"
          in
          Hashtbl.replace assigned inst_name port)
    non_rt;
  let declared = List.map fst groups in
  let synthetic =
    List.filter_map
      (fun (inst_name, _, _) ->
        let g = Hashtbl.find assigned inst_name in
        if List.mem g declared then None else Some g)
      non_rt
  in
  let seen = Hashtbl.create 8 in
  let group_order =
    List.filter
      (fun n ->
        if Hashtbl.mem seen n then false
        else (
          Hashtbl.add seen n ();
          true))
      (declared @ synthetic)
  in
  let group_index name =
    let rec find i = function
      | [] -> max_int
      | n :: _ when n = name -> i
      | _ :: rest -> find (i + 1) rest
    in
    find 0 group_order
  in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun (inst_name, _, _) ->
        let my_group = Hashtbl.find assigned inst_name in
        let my_idx = group_index my_group in
        let deps = connection_targets inst_name all_conns in
        List.iter
          (fun dep_name ->
            match Hashtbl.find_opt assigned dep_name with
            | Some dep_group ->
                let dep_idx = group_index dep_group in
                if dep_idx > my_idx then (
                  Hashtbl.replace assigned dep_name my_group;
                  changed := true)
            | None -> ())
          deps)
      non_rt
  done;
  List.filter_map
    (fun gname ->
      let insts =
        List.filter
          (fun (inst_name, _, _) -> Hashtbl.find assigned inst_name = gname)
          non_rt
      in
      if insts <> [] then Some (gname, insts) else None)
    group_order

(** For each group, compute which values it must return. This includes both
    instances produced by this group and pass-through values received from
    earlier groups that later groups still need. *)
let cross_group_exports partitioned all_conns =
  let n = List.length partitioned in
  let all_up_to =
    Array.init n (fun i ->
        List.concat_map
          (fun (_, insts) -> List.map (fun (name, _, _) -> name) insts)
          (List.filteri (fun j _ -> j <= i) partitioned))
  in
  List.mapi
    (fun i (_gname, _insts) ->
      if i = n - 1 then []
      else
        let later_inst_names =
          List.concat_map
            (fun (_, later_insts) ->
              List.map (fun (nm, _, _) -> nm) later_insts)
            (List.filteri (fun j _ -> j > i) partitioned)
        in
        let later_deps =
          List.concat_map
            (fun later_name -> connection_targets later_name all_conns)
            later_inst_names
        in
        List.filter (fun name -> List.mem name later_deps) all_up_to.(i))
    partitioned

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

(* ── Topology mode (functor-application) ──────────────────────────── *)

(* ── Topology code generation ─────────────────────────────────────── *)

(* Resolve the value for a component param on an instance.  Priority:
   1. [@ ocaml.param name "value"] annotation (per-topology build-time)
   2. Init spec [phase N "code"] where N = param index (per-instance)
   3. [None] — runtime Cmdliner term using the param default *)
let resolve_param_value inst_annots inst_name (ci : Ast.def_component_instance)
    idx (p : Ast.spec_param) =
  let param_name = camel_to_snake p.param_name.data in
  let annot_overrides = instance_param_annotations inst_annots inst_name in
  match Hashtbl.find_opt annot_overrides param_name with
  | Some v -> Some v
  | None ->
      let init_overrides = init_spec_overrides ci in
      Hashtbl.find_opt init_overrides idx

(** Resolve the source instance variable for a runtime labelled argument
    targeting [inst_name]. Returns the sanitized instance name of the Runtime
    instance providing the argument. *)
let resolve_runtime_arg_source inst_name arg connections =
  List.find_map
    (fun (conn : Ast.connection) ->
      let to_inst = pid_inst_name conn.conn_to_port.data in
      if
        to_inst = inst_name
        && camel_to_snake conn.conn_from_port.data.pid_port.data = arg
      then Some (sanitize_ident (pid_inst_name conn.conn_from_port.data))
      else None)
    connections

(** Emit runtime labelled arguments on a connect call. Required arguments are
    emitted as [~arg:(inst__arg ())], referencing the Cmdliner-registered term.
    Optional arguments are omitted entirely, letting the callee use its default
    value. *)
let pp_runtime_labelled_args ppf _inst_annots inst_name args connections =
  List.iter
    (fun (arg, optional) ->
      if optional then ()
      else
        match resolve_runtime_arg_source inst_name arg connections with
        | Some inst_var -> pf ppf " ~%s:(%s__%s ())" arg inst_var arg
        | None -> pf ppf " ~%s" arg)
    args

(** Emit the connect expression for a single instance: [Mod.method args]. Does
    not emit the [let*] prefix or [in] suffix — those are added by the caller.
*)
let pp_instance_expr ppf inst_name (ci : Ast.def_component_instance)
    (comp : Ast.def_component) connections sorted inst_annots =
  let inst_var = sanitize_ident inst_name in
  let mod_name = constructor_name inst_name in
  let method_name =
    sync_input_port_name comp |> Option.value ~default:"connect"
  in
  let targets = target_instances inst_name comp connections sorted in
  let rt_args = runtime_labelled_args inst_name sorted connections in
  let params = component_params comp in
  let config_ports = unconnected_input_ports inst_name comp connections in
  (* Exclude the sync input port from config_ports — it determines the method
     name, not a labeled argument. *)
  let config_ports =
    List.filter
      (fun (p : Ast.port_instance_general) ->
        camel_to_snake p.gen_name.data <> method_name)
      config_ports
  in
  pf ppf "%s.%s" mod_name method_name;
  pp_runtime_labelled_args ppf inst_annots inst_name rt_args connections;
  let has_any_arg = rt_args <> [] in
  let has_any_arg = ref has_any_arg in
  List.iteri
    (fun i ((p : Ast.spec_param), positional, optional) ->
      let param_name = camel_to_snake p.param_name.data in
      let prefix = if optional then "?" else "~" in
      match resolve_param_value inst_annots inst_name ci i p with
      | Some code ->
          has_any_arg := true;
          if positional then pf ppf " %s" code
          else pf ppf " %s%s:%s" prefix param_name code
      | None ->
          if optional then () (* omit unresolved optional params *)
          else (
            has_any_arg := true;
            if positional then pf ppf " (%s__%s ())" inst_var param_name
            else pf ppf " ~%s:(%s__%s ())" param_name inst_var param_name))
    params;
  List.iter
    (fun (p : Ast.port_instance_general) ->
      has_any_arg := true;
      pf ppf " ~%s" (sanitize_ident p.gen_name.data))
    config_ports;
  List.iter
    (fun (target_inst, _) ->
      has_any_arg := true;
      pf ppf " %s" (sanitize_ident target_inst))
    targets;
  if not !has_any_arg then pf ppf " ()"

(** Emit a lazy group binding. [prev_group] is the name and exports of the
    previous group (if any). [exports] lists instance names this group must
    return for later groups. Each group is a [lazy] value that memoises its
    result, so forcing it multiple times is safe. *)
let pp_group_function ppf ~prev_group group_name insts all_conns sorted
    inst_annots exports =
  let n = List.length insts in
  let has_cross_deps = prev_group <> None in
  let needs_lwt_syntax = n > 1 || has_cross_deps in
  (* Determine if we need a tuple return *)
  let last_inst_name =
    match List.rev insts with (name, _, _) :: _ -> name | [] -> ""
  in
  let need_tuple_return =
    match exports with
    | [] -> false
    | [ single ] -> single <> last_inst_name
    | _ -> true
  in
  if not needs_lwt_syntax then
    (* Single instance, no cross-deps: one-liner *)
    match insts with
    | [ (inst_name, ci, comp) ] ->
        pf ppf "@,@,let %s = lazy (" group_name;
        pp_instance_expr ppf inst_name ci comp all_conns sorted inst_annots;
        pf ppf ")"
    | _ -> ()
  else (
    pf ppf "@,@,let %s = lazy (" group_name;
    pf ppf "@,  let open Lwt.Syntax in";
    (* Cross-group deps from previous group *)
    (match prev_group with
    | None -> ()
    | Some (prev_name, prev_exports) -> (
        match prev_exports with
        | [ name ] ->
            pf ppf "@,  let* %s = Lazy.force %s in" (sanitize_ident name)
              prev_name
        | _ ->
            let names = List.map sanitize_ident prev_exports in
            pf ppf "@,  let* (%s) = Lazy.force %s in" (String.concat ", " names)
              prev_name));
    (* let* chain for each instance *)
    List.iteri
      (fun i (inst_name, ci, (comp : Ast.def_component)) ->
        let is_last = i = n - 1 in
        if is_last && not need_tuple_return then (
          pf ppf "@,  ";
          pp_instance_expr ppf inst_name ci comp all_conns sorted inst_annots)
        else (
          pf ppf "@,  let* %s = " (sanitize_ident inst_name);
          pp_instance_expr ppf inst_name ci comp all_conns sorted inst_annots;
          pf ppf " in"))
      insts;
    (* Tuple return for multi-export *)
    if need_tuple_return then
      pf ppf "@,  Lwt.return (%s)"
        (String.concat ", " (List.map sanitize_ident exports));
    pf ppf ")")

(** Emit a single Cmdliner term registration for one unresolved param. *)
let pp_one_cmdliner_term ppf ~inst_var (p : Ast.spec_param) =
  let param_name = camel_to_snake p.param_name.data in
  let conv = cmdliner_conv_of_fpp_type p.param_type.data in
  let default =
    match p.param_default with
    | Some e -> ocaml_literal_of_expr e.data
    | None -> "\"\""
  in
  pf ppf "@,let %s__%s =" inst_var param_name;
  pf ppf "@,  let doc = Cmdliner.Arg.info ~doc:%S [%S] in" param_name
    (inst_var ^ "-"
    ^ String.map (fun c -> if c = '_' then '-' else c) param_name);
  pf ppf "@,  Mirage_runtime.register_arg Cmdliner.Arg.(value & opt %s %s doc)"
    conv default

(** Emit Cmdliner term registrations for component params that are not
    overridden by annotations or init specs. *)
let pp_param_cmdliner_terms ppf inst_annots sorted =
  List.iter
    (fun (inst_name, ci, (comp : Ast.def_component)) ->
      if is_runtime_component comp then ()
      else
        let params = component_params comp in
        let inst_var = sanitize_ident inst_name in
        List.iteri
          (fun i ((p : Ast.spec_param), _positional, optional) ->
            if
              resolve_param_value inst_annots inst_name ci i p = None
              && not optional
            then pp_one_cmdliner_term ppf ~inst_var p)
          params)
    sorted

let pp_module_aliases ppf inst_annots all_conns module_break sorted =
  List.iter
    (fun (inst_name, _ci, (comp : Ast.def_component)) ->
      if is_runtime_component comp then ()
      else
        let targets = target_instances inst_name comp all_conns sorted in
        if targets = [] then
          match instance_bound_module inst_annots inst_name with
          | Some concrete_mod ->
              let mod_name = constructor_name inst_name in
              if mod_name <> concrete_mod then (
                module_break ();
                pf ppf "module %s = %s" mod_name concrete_mod)
          | None -> ())
    sorted

(** Resolve the functor path for a non-leaf instance. Priority: instance
    annotation, component annotation, default [Instance_name.Make]. *)
let resolve_functor_path inst_annots inst_name ca =
  match instance_bound_module inst_annots inst_name with
  | Some s -> s
  | None -> (
      match ca.module_path with
      | Some s -> s
      | None -> constructor_name inst_name ^ ".Make")

let pp_functor_applications ppf tu inst_annots all_conns module_break sorted =
  List.iter
    (fun (inst_name, ci, (comp : Ast.def_component)) ->
      if is_runtime_component comp then ()
      else
        let targets = target_instances inst_name comp all_conns sorted in
        if targets <> [] then (
          let mod_name = constructor_name inst_name in
          let ca =
            parse_ocaml_annotations
              (component_annots tu ci.Ast.inst_component.data)
          in
          let path = resolve_functor_path inst_annots inst_name ca in
          module_break ();
          pf ppf "module %s = %s" mod_name path;
          List.iter
            (fun (target_inst, _) ->
              pf ppf "(%s)" (constructor_name target_inst))
            targets))
    sorted

(** Pretty-print topology body. Module aliases and functor applications are at
    top level, followed by one function per connection group. *)
let pp_topology_body ppf tu topo sorted groups =
  let all_conns = all_connections groups in
  let inst_annots = instance_annotations topo in
  let first_module = ref true in
  let module_break () =
    if !first_module then (
      pf ppf "@,";
      first_module := false);
    pf ppf "@,"
  in
  let non_rt = filter_non_runtime sorted in
  pp_module_aliases ppf inst_annots all_conns module_break non_rt;
  pp_functor_applications ppf tu inst_annots all_conns module_break non_rt;
  (* Cmdliner registrations for component params not overridden *)
  pp_param_cmdliner_terms ppf inst_annots non_rt;
  (* Group functions *)
  let partitioned = partition_instances_by_group non_rt groups all_conns in
  let exports = cross_group_exports partitioned all_conns in
  let _prev =
    List.fold_left2
      (fun prev_group (gname, insts) group_exports ->
        pp_group_function ppf ~prev_group gname insts all_conns sorted
          inst_annots group_exports;
        if group_exports = [] then None else Some (gname, group_exports))
      None partitioned exports
  in
  ()

(** Whether a topology would produce OCaml code. Any topology with non-runtime
    instances produces output. *)
let topology_has_output tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let connections = all_connections (collect_direct_connections topo) in
  let sorted = topo_sort_instances resolved connections in
  filter_non_runtime sorted <> []

let topology_is_fully_bound tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let connections = all_connections (collect_direct_connections topo) in
  let sorted = topo_sort_instances resolved connections in
  filter_non_runtime sorted <> []

(** Return connect function names for a topology (one per connection group). *)
let topology_connect_names tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let groups = collect_direct_connections topo in
  List.map fst groups

(** Pretty-print a topology as OCaml code. Empty topologies produce no output.
*)
let pp_topology tu ppf (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let groups = collect_direct_connections topo in
  let connections = all_connections groups in
  let sorted = topo_sort_instances resolved connections in
  let non_rt = filter_non_runtime sorted in
  if non_rt = [] then ()
  else (
    pf ppf "@[<v>(* Generated by ofpp to-ml from topology %s *)"
      topo.topo_name.data;
    pp_topology_body ppf tu topo sorted groups;
    pf ppf "@]@.")

(** Emit a [let () = Lwt_main.run (...)] entry point. Each element is
    [(topo_module_name, func_name)] where [func_name] is a lazy group binding.
    Uses [@.] (print_newline) instead of [@,] because this is called outside any
    formatting box. *)
let pp_main_entry_multi ppf topos =
  let wrap = List.length topos > 1 in
  match topos with
  | [] -> ()
  | [ (_, func_name) ] ->
      pf ppf "let () =@.  Lwt_main.run (Lazy.force %s |> Lwt.map ignore)@."
        func_name
  | _ ->
      pf ppf "let () =@.  Lwt_main.run begin@.";
      pf ppf "    let open Lwt.Syntax in@.";
      List.iter
        (fun (topo_name, func_name) ->
          let var = camel_to_snake topo_name in
          let prefix = if wrap then topo_name ^ "." else "" in
          pf ppf "    let* _%s = Lazy.force %s%s in@." var prefix func_name)
        topos;
      pf ppf "    Lwt.return ()@.";
      pf ppf "  end@."

(* ── .mli generation ─────────────────────────────────────────────── *)

(** Pretty-print the .mli for a topology. Emits module aliases and function
    signatures for each connection group. Runtime instances are excluded. *)
let pp_topology_mli tu ppf (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let groups = collect_direct_connections topo in
  let connections = all_connections groups in
  let sorted = topo_sort_instances resolved connections in
  let non_rt = filter_non_runtime sorted in
  if non_rt = [] then ()
  else begin
    let all_conns = connections in
    let inst_annots = instance_annotations topo in
    pf ppf "@[<v>(** Generated by ofpp to-ml from topology %s. *)"
      topo.topo_name.data;
    let first_module = ref true in
    List.iter
      (fun ( inst_name,
             (ci : Ast.def_component_instance),
             (comp : Ast.def_component) ) ->
        let mod_name = constructor_name inst_name in
        let ca =
          parse_ocaml_annotations (component_annots tu ci.inst_component.data)
        in
        let targets = target_instances inst_name comp all_conns sorted in
        match (ca.sig_path, targets) with
        | Some sig_path, _ ->
            if !first_module then (
              pf ppf "@,";
              first_module := false);
            pf ppf "@,module %s : %s" mod_name sig_path
        | None, [] -> (
            match instance_bound_module inst_annots inst_name with
            | None -> ()
            | Some concrete_mod ->
                if mod_name <> concrete_mod then (
                  if !first_module then (
                    pf ppf "@,";
                    first_module := false);
                  pf ppf "@,module %s = %s" mod_name concrete_mod))
        | None, _ -> ())
      non_rt;
    let partitioned = partition_instances_by_group non_rt groups all_conns in
    let exports = cross_group_exports partitioned all_conns in
    pf ppf "@,";
    List.iter2
      (fun (gname, _insts) group_exports ->
        let ret_type =
          match group_exports with
          | [] -> "unit Lwt.t"
          | [ name ] -> constructor_name name ^ ".t Lwt.t"
          | _ ->
              "("
              ^ String.concat " * "
                  (List.map (fun n -> constructor_name n ^ ".t") group_exports)
              ^ ") Lwt.t"
        in
        pf ppf "@,val %s : %s Lazy.t" gname ret_type)
      partitioned exports;
    pf ppf "@]@."
  end

(** Return group function names for the topology. Each element is
    [(func_name, func_name)]. Used by [pp_entry_point] to call the last group
    function. *)
let topology_active_instance_names tu (topo : Ast.def_topology) =
  let topo = flatten_topology tu topo in
  let resolved = resolve_topology_instances tu topo in
  let groups = collect_direct_connections topo in
  let connections = all_connections groups in
  let sorted = topo_sort_instances resolved connections in
  let non_rt = filter_non_runtime sorted in
  let partitioned = partition_instances_by_group non_rt groups connections in
  List.map (fun (gname, _) -> (gname, gname)) partitioned

(** Emit a Mirage_runtime-based entry point that registers cmdliner arguments,
    parses [Mirage_bootvar.argv], initialises RNG and logging, calls the last
    group function, and runs via [Unix_os.Main.run]. Each element of [names] is
    [(func_name, func_name)]. *)
let pp_entry_point ppf ~topo_name names =
  match names with
  | [] -> ()
  | _ ->
      pf ppf
        "let mirage_runtime_delay__key = Mirage_runtime.register_arg @@@@ \
         Mirage_runtime.delay@.";
      pf ppf
        "let mirage_runtime_logs__key = Mirage_runtime.register_arg @@@@ \
         Mirage_runtime.logs@.";
      pf ppf "let cmdliner_stdlib__key = Mirage_runtime.register_arg @@@@@.";
      pf ppf
        "  Cmdliner_stdlib.setup ~backtrace:(Some true) \
         ~randomize_hashtables:(Some true) ()@.@.";
      pf ppf "let () =@.  let t =@.";
      pf ppf "    let open Lwt.Syntax in@.";
      pf ppf
        "    let* () = Lwt.return (Mirage_runtime.(with_argv (runtime_args ()) \
         %S (Mirage_bootvar.argv ()))) in@."
        topo_name;
      pf ppf "    let _ = cmdliner_stdlib__key () in@.";
      pf ppf
        "    let* () = Mirage_sleep.ns (Duration.of_sec \
         (mirage_runtime_delay__key ())) in@.";
      pf ppf "    let reporter = Mirage_logs.create () in@.";
      pf ppf
        "    Mirage_runtime.set_level ~default:(Some Logs.Info) \
         (mirage_runtime_logs__key ());@.";
      pf ppf "    Logs.set_reporter reporter;@.";
      pf ppf
        "    let* _ = Mirage_crypto_rng_mirage.initialize (module \
         Mirage_crypto_rng.Fortuna) in@.";
      pf ppf "    Mirage_runtime.set_name %S;@." topo_name;
      let last_func = fst (List.nth names (List.length names - 1)) in
      pf ppf "    let* _ = Lazy.force %s in@." last_func;
      pf ppf "    Lwt.return ()@.";
      pf ppf "  in@.";
      pf ppf "  Unix_os.Main.run t; exit 0@."

(** Expression and spec_loc validation for TU-level definitions.

    Validates constant expressions, array/enum/struct defaults, and spec_loc
    paths across the translation unit. This module is internal to the [fpp]
    library. *)

open Check_env
open Check_tu_env

(* ── Expression checks for constant definitions ────────────────────── *)

let rec check_constant_exprs ~scope tu_env members =
  List.concat_map
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_constant c ->
          check_expr ~scope tu_env c.const_value
          @ check_array_expr ~scope tu_env c.const_value
          @ check_struct_expr_dupes ~scope c.const_value
      | Ast.Mod_def_array a ->
          let size_diags = check_expr ~scope tu_env a.array_size in
          let default_diags =
            match a.array_default with
            | Some e ->
                check_expr ~scope tu_env e @ check_struct_expr_dupes ~scope e
            | None -> []
          in
          size_diags @ default_diags
      | Ast.Mod_def_enum e -> (
          List.concat_map
            (fun ann ->
              let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
              match c.enum_const_value with
              | Some e -> check_expr ~scope tu_env e
              | None -> [])
            e.enum_constants
          @
          match e.enum_default with
          | Some e -> check_expr ~scope tu_env e
          | None -> [])
      | Ast.Mod_def_struct s -> (
          match s.struct_default with
          | Some e ->
              check_expr ~scope tu_env e @ check_struct_expr_dupes ~scope e
          | None -> [])
      | Ast.Mod_def_module m ->
          let sub =
            match SMap.find_opt m.module_name.data tu_env.modules with
            | Some e -> e
            | None -> tu_env
          in
          check_constant_exprs
            ~scope:(scope ^ "." ^ m.module_name.data)
            sub m.module_members
      | _ -> [])
    members

(* ── Undefined constant reference checks ──────────────────────────── *)

let rec expr_to_ident_list (e : Ast.expr Ast.node) =
  match e.data with
  | Ast.Expr_ident id -> Some [ id ]
  | Ast.Expr_dot (inner, field) -> (
      match expr_to_ident_list inner with
      | Some ids -> Some (ids @ [ field ])
      | None -> None)
  | _ -> None

let list_to_qual_ident = function
  | [] -> assert false
  | first :: rest ->
      List.fold_left
        (fun qi id -> Ast.Qualified ({ data = qi; loc = first.Ast.loc }, id))
        (Ast.Unqualified first) rest

let any_prefix_resolves tu_env ids =
  let len = List.length ids in
  (* First try the full path *)
  let qi = list_to_qual_ident ids in
  match resolve_symbol tu_env qi with
  | Some _ -> true
  | None ->
      (* Then try shorter prefixes - but only non-module symbols *)
      let rec try_n n =
        if n <= 0 then false
        else
          let prefix = List.filteri (fun i _ -> i < n) ids in
          let qi = list_to_qual_ident prefix in
          match resolve_symbol tu_env qi with
          | Some (Sk_module, _) ->
              (* Module alone is not enough; the full path must resolve *)
              try_n (n - 1)
          | Some _ -> true
          | None -> try_n (n - 1)
      in
      try_n (len - 1)

let check_undef_constant_refs ~scope ~root_env tu_env ~extra
    (e : Ast.expr Ast.node) =
  let rec walk (e : Ast.expr Ast.node) =
    match e.data with
    | Ast.Expr_ident id ->
        if
          Option.is_none (SMap.find_opt id.data tu_env.constants)
          && Option.is_none (resolve_symbol tu_env (Ast.Unqualified id))
          && Option.is_none (resolve_symbol root_env (Ast.Unqualified id))
          && not (SSet.mem id.data extra)
        then
          [
            error ~sm_name:scope id.loc
              (Fmt.str "undefined symbol '%s'" id.data);
          ]
        else []
    | Ast.Expr_dot (_, _) -> (
        match expr_to_ident_list e with
        | Some ids ->
            if
              any_prefix_resolves tu_env ids || any_prefix_resolves root_env ids
            then []
            else
              let name =
                String.concat "."
                  (List.map (fun (n : Ast.ident Ast.node) -> n.data) ids)
              in
              [
                error ~sm_name:scope e.loc
                  (Fmt.str "undefined symbol '%s'" name);
              ]
        | None ->
            let inner = match e.data with Ast.Expr_dot (i, _) -> i | _ -> e in
            walk inner)
    | Ast.Expr_paren inner -> walk inner
    | Ast.Expr_unop (_, inner) -> walk inner
    | Ast.Expr_binop (l, _, r) -> walk l @ walk r
    | Ast.Expr_array es -> List.concat_map walk es
    | Ast.Expr_struct ms ->
        List.concat_map
          (fun (m : Ast.struct_member Ast.node) -> walk m.data.sm_value)
          ms
    | Ast.Expr_subscript (a, i) -> walk a @ walk i
    | _ -> []
  in
  walk e

let rec check_undef_constants ~scope ~root_env tu_env members =
  List.concat_map
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_constant c ->
          check_undef_constant_refs ~scope ~root_env tu_env ~extra:SSet.empty
            c.const_value
      | Ast.Mod_def_enum e ->
          let known = ref SSet.empty in
          List.concat_map
            (fun ann ->
              let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
              let diags =
                match c.enum_const_value with
                | Some expr ->
                    check_undef_constant_refs ~scope ~root_env tu_env
                      ~extra:!known expr
                | None -> []
              in
              known := SSet.add c.enum_const_name.data !known;
              diags)
            e.enum_constants
      | Ast.Mod_def_module m ->
          let sub =
            match SMap.find_opt m.module_name.data tu_env.modules with
            | Some e -> e
            | None -> tu_env
          in
          check_undef_constants
            ~scope:(scope ^ "." ^ m.module_name.data)
            ~root_env sub m.module_members
      | _ -> [])
    members

(* ── Dictionary annotation checks ─────────────────────────────────── *)

let def_is_dictionary name members =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Mod_def_abs_type t -> t.abs_name.data = name && t.abs_dictionary
      | Ast.Mod_def_alias_type t ->
          t.alias_name.data = name && t.alias_dictionary
      | Ast.Mod_def_array a -> a.array_name.data = name && a.array_dictionary
      | Ast.Mod_def_struct s -> s.struct_name.data = name && s.struct_dictionary
      | Ast.Mod_def_enum e -> e.enum_name.data = name && e.enum_dictionary
      | Ast.Mod_def_constant c -> c.const_name.data = name && c.const_dictionary
      | _ -> false)
    members

let rec is_type_displayable members (tn : Ast.type_name) =
  match tn with
  | Ast.Type_bool | Ast.Type_int _ | Ast.Type_float _ | Ast.Type_string _ ->
      true
  | Ast.Type_qual qi ->
      let name = Ast.qual_ident_to_string qi.data in
      is_named_type_displayable members name

and is_named_type_displayable members name =
  let def = ref None in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Mod_def_abs_type t when t.abs_name.data = name ->
          def := Some `Abstract
      | Ast.Mod_def_alias_type t when t.alias_name.data = name ->
          def := Some (`Alias t.alias_type.data)
      | Ast.Mod_def_array a when a.array_name.data = name ->
          def := Some (`Array a.array_elt_type.data)
      | Ast.Mod_def_struct s when s.struct_name.data = name ->
          def :=
            Some
              (`Struct
                 (List.map
                    (fun ann ->
                      let m : Ast.struct_type_member =
                        (Ast.unannotate ann).Ast.data
                      in
                      m.struct_mem_type.data)
                    s.struct_members))
      | _ -> ())
    members;
  match !def with
  | None -> true
  | Some `Abstract -> false
  | Some (`Alias tn) -> is_type_displayable members tn
  | Some (`Array tn) -> is_type_displayable members tn
  | Some (`Struct tns) -> List.for_all (is_type_displayable members) tns

(* ── spec_loc validation ───────────────────────────────────────────── *)

let check_path ~scope (sl : Ast.spec_loc) =
  let path = sl.loc_path.data in
  let source_file = sl.loc_path.loc.file in
  let source_base = Filename.basename source_file in
  let declared_base = Filename.basename path in
  if source_base <> declared_base && declared_base <> "" then
    [
      error ~sm_name:scope sl.loc_path.loc
        (Fmt.str "location path '%s' does not match source file '%s'" path
           source_base);
    ]
  else []

let rec check_spec_locs ~scope members =
  List.concat_map
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_spec_loc sl -> (
          let name = Ast.qual_ident_to_string sl.loc_name.data in
          match sl.loc_kind with
          | Ast.Loc_dictionary_type ->
              if not (def_is_dictionary name members) then
                [
                  error ~sm_name:scope sl.loc_name.loc
                    (Fmt.str
                       "locate dictionary type '%s' does not match a \
                        dictionary definition"
                       name);
                ]
              else check_path ~scope sl
          | Ast.Loc_type ->
              if def_is_dictionary name members then
                [
                  error ~sm_name:scope sl.loc_name.loc
                    (Fmt.str
                       "type '%s' is a dictionary type; use 'locate dictionary \
                        type'"
                       name);
                ]
              else check_path ~scope sl
          | Ast.Loc_constant ->
              if def_is_dictionary name members then
                [
                  error ~sm_name:scope sl.loc_name.loc
                    (Fmt.str
                       "constant '%s' is a dictionary constant; use 'locate \
                        dictionary constant'"
                       name);
                ]
              else check_path ~scope sl
          | _ -> check_path ~scope sl)
      | Ast.Mod_def_module m ->
          check_spec_locs
            ~scope:(scope ^ "." ^ m.module_name.data)
            m.module_members
      | _ -> [])
    members

(* ── Shared validation helpers ────────────────────────────────────── *)

let check_type_string_size ~scope tu_env (type_node : Ast.type_name Ast.node) =
  match type_node.data with
  | Ast.Type_string (Some sz) -> (
      let v, d = eval_expr ~scope tu_env sz in
      d
      @
      match v with
      | Val_int n when n < 0 ->
          [ error ~sm_name:scope sz.loc "string size must be non-negative" ]
      | Val_int n when n > 0x7FFFFFFF ->
          [ error ~sm_name:scope sz.loc "string size too large" ]
      | Val_string _ ->
          [
            error ~sm_name:scope sz.loc
              "string size must be a numeric expression";
          ]
      | _ -> [])
  | _ -> []

let check_format_against_type ~scope tu_env fmt_opt type_node desc =
  match fmt_opt with
  | None -> []
  | Some (fmt : string Ast.node) -> (
      check_format_string ~scope fmt.loc fmt.data 1
      @
      let spec = extract_format_spec fmt.data in
      match spec with
      | Fmt_integer ->
          if
            (not (is_integer_type type_node.Ast.data))
            && not (is_integer_type_resolved tu_env type_node)
          then
            [
              error ~sm_name:scope fmt.loc
                (Fmt.str "format specifier requires integer type for %s" desc);
            ]
          else []
      | Fmt_float prec -> (
          (if
             (not (is_float_type type_node.Ast.data))
             && not (is_float_type_resolved tu_env type_node)
           then
             [
               error ~sm_name:scope fmt.loc
                 (Fmt.str "format specifier requires floating-point type for %s"
                    desc);
             ]
           else [])
          @
          match prec with
          | Some n when n > 100 ->
              [
                error ~sm_name:scope fmt.loc
                  (Fmt.str "precision value %d is out of range" n);
              ]
          | _ -> [])
      | Fmt_default ->
          if
            (not (is_numeric_type type_node.Ast.data))
            && not (is_numeric_resolved_tu tu_env type_node)
          then
            [
              error ~sm_name:scope fmt.loc
                (Fmt.str "format specifier on non-numeric %s" desc);
            ]
          else [])

(* ── Array definition checks ──────────────────────────────────────── *)

let check_array_default ~scope tu_env (a : Ast.def_array) size_val =
  match a.array_default with
  | None -> []
  | Some def ->
      let dv, _ = eval_expr ~scope tu_env def in
      let elt_is_string =
        match a.array_elt_type.data with
        | Ast.Type_string _ -> true
        | _ -> false
      in
      let type_diags =
        match dv with
        | Val_string _ when not elt_is_string ->
            [
              error ~sm_name:scope def.loc
                (Fmt.str
                   "array '%s' default must be an array expression, got string"
                   a.array_name.data);
            ]
        | _ -> []
      in
      let size_diags =
        match (size_val, def.data) with
        | Val_int expected_size, Ast.Expr_array elts ->
            let actual = List.length elts in
            if actual <> expected_size then
              [
                error ~sm_name:scope def.loc
                  (Fmt.str
                     "array default has %d element%s but declared size is %d"
                     actual
                     (if actual <> 1 then "s" else "")
                     expected_size);
              ]
            else []
        | _ -> []
      in
      type_diags @ size_diags

let check_array_def ~scope tu_env (a : Ast.def_array) =
  let diags = ref [] in
  let add ds = diags := List.rev_append ds !diags in
  let v, d = eval_expr ~scope tu_env a.array_size in
  add d;
  (match v with
  | Val_int n when n <= 0 ->
      add
        [
          error ~sm_name:scope a.array_size.loc
            (Fmt.str "array size must be positive (got %d)" n);
        ]
  | Val_int n when n > 0x7FFFFFFF ->
      add [ error ~sm_name:scope a.array_size.loc "array size too large" ]
  | _ -> ());
  add (check_type_string_size ~scope tu_env a.array_elt_type);
  add
    (check_format_against_type ~scope tu_env a.array_format a.array_elt_type
       (Fmt.str "array '%s'" a.array_name.data));
  add (check_array_default ~scope tu_env a v);
  List.rev !diags

(* ── Enum definition checks ──────────────────────────────────────── *)

let check_enum_constant_types ~scope tu_env (e : Ast.def_enum) =
  List.concat_map
    (fun ann ->
      let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
      match c.enum_const_value with
      | Some expr -> (
          let v, _ = eval_expr ~scope tu_env expr in
          match v with
          | Val_string _ | Val_bool _ ->
              [
                error ~sm_name:scope expr.loc
                  (Fmt.str "enum constant '%s' value must be numeric"
                     c.enum_const_name.data);
              ]
          | _ -> [])
      | None -> [])
    e.enum_constants

let check_enum_duplicate_values ~scope tu_env (e : Ast.def_enum) =
  let values = Hashtbl.create 8 in
  let next_implicit = ref 0 in
  let diags = ref [] in
  List.iter
    (fun ann ->
      let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
      let value =
        match c.enum_const_value with
        | Some expr -> (
            let v, _ = eval_expr ~scope tu_env expr in
            match v with
            | Val_int n ->
                next_implicit := n + 1;
                Some n
            | _ -> None)
        | None ->
            let n = !next_implicit in
            incr next_implicit;
            Some n
      in
      match value with
      | Some n -> (
          match Hashtbl.find_opt values n with
          | Some prev_name ->
              diags :=
                error ~sm_name:scope c.enum_const_name.loc
                  (Fmt.str "enum constant '%s' has same value %d as '%s'"
                     c.enum_const_name.data n prev_name)
                :: !diags
          | None -> Hashtbl.replace values n c.enum_const_name.data)
      | None -> ())
    e.enum_constants;
  (values, List.rev !diags)

let check_enum_mixed_values ~scope (e : Ast.def_enum) =
  let has_explicit = ref false in
  List.concat_map
    (fun ann ->
      let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
      match c.enum_const_value with
      | Some _ ->
          has_explicit := true;
          []
      | None ->
          if !has_explicit then
            [
              error ~sm_name:scope c.enum_const_name.loc
                (Fmt.str
                   "enum constant '%s' must have explicit value after explicit \
                    constant"
                   c.enum_const_name.data);
            ]
          else [])
    e.enum_constants

let check_enum_default ~scope _tu_env _values (e : Ast.def_enum) =
  let const_names =
    List.map
      (fun ann ->
        let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
        c.enum_const_name.data)
      e.enum_constants
  in
  match e.enum_default with
  | None -> []
  | Some d -> (
      match d.data with
      | Ast.Expr_ident id ->
          if not (List.mem id.data const_names) then
            [
              error ~sm_name:scope d.loc
                (Fmt.str "enum default '%s' is not a valid enumerator" id.data);
            ]
          else []
      | Ast.Expr_dot _ -> (
          match expr_to_ident_list d with
          | Some ids ->
              let last = List.rev ids |> List.hd in
              if not (List.mem last.Ast.data const_names) then
                [
                  error ~sm_name:scope d.loc
                    (Fmt.str "enum default '%s' is not a valid enumerator"
                       last.data);
                ]
              else []
          | None ->
              [
                error ~sm_name:scope d.loc
                  "enum default must be an enumerator name";
              ])
      | _ ->
          [
            error ~sm_name:scope d.loc "enum default must be an enumerator name";
          ])

let check_enum_def ~scope tu_env (e : Ast.def_enum) =
  let empty =
    if e.enum_constants = [] then
      [
        error ~sm_name:scope e.enum_name.loc
          (Fmt.str "enum '%s' has no constants" e.enum_name.data);
      ]
    else []
  in
  let rep_type =
    match e.enum_type with
    | Some t ->
        if not (is_integer_type t.data) then
          if not (is_integer_type_resolved tu_env t) then
            [
              error ~sm_name:scope t.loc
                (Fmt.str "enum rep type must be an integer type");
            ]
          else []
        else []
    | None -> []
  in
  let const_types = check_enum_constant_types ~scope tu_env e in
  let values, dup_diags = check_enum_duplicate_values ~scope tu_env e in
  let mixed = check_enum_mixed_values ~scope e in
  let default = check_enum_default ~scope tu_env values e in
  empty @ rep_type @ const_types @ dup_diags @ mixed @ default

(* ── Struct definition checks ────────────────────────────────────── *)

let check_struct_mem_size ~scope tu_env (m : Ast.struct_type_member) =
  match m.struct_mem_size with
  | None -> []
  | Some sz -> (
      let v, d = eval_expr ~scope tu_env sz in
      d
      @
      match v with
      | Val_int n when n <= 0 ->
          [
            error ~sm_name:scope sz.loc
              (Fmt.str "struct member array size must be positive (got %d)" n);
          ]
      | Val_string _ ->
          [
            error ~sm_name:scope sz.loc
              "struct member array size must be a numeric expression";
          ]
      | _ -> [])

let check_struct_member ~scope tu_env (m : Ast.struct_type_member) =
  check_type_string_size ~scope tu_env m.struct_mem_type
  @ check_struct_mem_size ~scope tu_env m
  @ check_format_against_type ~scope tu_env m.struct_mem_format
      m.struct_mem_type
      (Fmt.str "member '%s'" m.struct_mem_name.data)

let check_struct_def ~scope tu_env (s : Ast.def_struct) =
  let member_diags =
    List.concat_map
      (fun ann ->
        check_struct_member ~scope tu_env (Ast.unannotate ann).Ast.data)
      s.struct_members
  in
  let default_diags =
    match s.struct_default with
    | Some e -> (
        match e.data with
        | Ast.Expr_struct ms ->
            let known =
              List.map
                (fun ann ->
                  let m : Ast.struct_type_member =
                    (Ast.unannotate ann).Ast.data
                  in
                  m.struct_mem_name.data)
                s.struct_members
            in
            List.concat_map
              (fun (m : Ast.struct_member Ast.node) ->
                if not (List.mem m.data.sm_name.data known) then
                  [
                    error ~sm_name:scope m.data.sm_name.loc
                      (Fmt.str "unknown member '%s' in struct '%s' default"
                         m.data.sm_name.data s.struct_name.data);
                  ]
                else [])
              ms
        | _ -> [])
    | None -> []
  in
  member_diags @ default_diags

(* ── Type alias checks ───────────────────────────────────────────── *)

let check_type_def ~scope tu_env members =
  List.concat_map
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_alias_type t -> (
          match t.alias_type.data with
          | Ast.Type_string (Some sz) -> (
              let v, d = eval_expr ~scope tu_env sz in
              d
              @
              match v with
              | Val_int n when n < 0 ->
                  [
                    error ~sm_name:scope sz.loc
                      "string size must be non-negative";
                  ]
              | Val_int n when n > 0x7FFFFFFF ->
                  [ error ~sm_name:scope sz.loc "string size too large" ]
              | Val_string _ ->
                  [
                    error ~sm_name:scope sz.loc
                      "string size must be a numeric expression";
                  ]
              | _ -> [])
          | _ -> [])
      | _ -> [])
    members

(* ── Array enum default check ─────────────────────────────────────── *)

let is_enum_type members (tn : Ast.type_name) =
  match tn with
  | Ast.Type_qual qi ->
      let name = Ast.qual_ident_to_string qi.data in
      List.exists
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Mod_def_enum e -> e.enum_name.data = name
          | _ -> false)
        members
  | _ -> false

let check_enum_array_default ~scope members (a : Ast.def_array) =
  if not (is_enum_type members a.array_elt_type.data) then []
  else
    match a.array_default with
    | None -> []
    | Some def -> (
        match def.data with
        | Ast.Expr_literal (Ast.Lit_int _)
        | Ast.Expr_literal (Ast.Lit_float _)
        | Ast.Expr_literal (Ast.Lit_bool _) ->
            [
              error ~sm_name:scope def.loc
                (Fmt.str
                   "array '%s' default must use an enum constant, not a literal"
                   a.array_name.data);
            ]
        | _ -> [])

(* ── TU-level definition checks ──────────────────────────────────── *)

let rec check_definitions ~scope tu_env members =
  List.concat_map
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_array a ->
          check_array_def ~scope tu_env a
          @ check_enum_array_default ~scope members a
      | Ast.Mod_def_enum e -> check_enum_def ~scope tu_env e
      | Ast.Mod_def_struct s -> check_struct_def ~scope tu_env s
      | Ast.Mod_def_module m ->
          let sub =
            match SMap.find_opt m.module_name.data tu_env.modules with
            | Some e -> e
            | None -> tu_env
          in
          check_definitions
            ~scope:(scope ^ "." ^ m.module_name.data)
            sub m.module_members
      | _ -> [])
    members

(* ── Dictionary displayability checks ─────────────────────────────── *)

let rec check_displayable_defs ~scope members =
  List.concat_map
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_array a when a.array_dictionary ->
          if not (is_type_displayable members a.array_elt_type.data) then
            [
              error ~sm_name:scope a.array_name.loc
                (Fmt.str "dictionary array '%s' element type is not displayable"
                   a.array_name.data);
            ]
          else []
      | Ast.Mod_def_struct s when s.struct_dictionary ->
          List.concat_map
            (fun ann ->
              let m : Ast.struct_type_member = (Ast.unannotate ann).Ast.data in
              if not (is_type_displayable members m.struct_mem_type.data) then
                [
                  error ~sm_name:scope m.struct_mem_name.loc
                    (Fmt.str
                       "dictionary struct '%s' member '%s' type is not \
                        displayable"
                       s.struct_name.data m.struct_mem_name.data);
                ]
              else [])
            s.struct_members
      | Ast.Mod_def_alias_type t when t.alias_dictionary ->
          if not (is_type_displayable members t.alias_type.data) then
            [
              error ~sm_name:scope t.alias_name.loc
                (Fmt.str "dictionary type '%s' aliases a non-displayable type"
                   t.alias_name.data);
            ]
          else []
      | Ast.Mod_def_constant c when c.const_dictionary -> (
          match c.const_value.data with
          | Ast.Expr_struct _ ->
              [
                error ~sm_name:scope c.const_name.loc
                  (Fmt.str
                     "dictionary constant '%s' has a non-displayable value"
                     c.const_name.data);
              ]
          | _ -> [])
      | Ast.Mod_def_module m ->
          check_displayable_defs
            ~scope:(scope ^ "." ^ m.module_name.data)
            m.module_members
      | _ -> [])
    members

(* ── Entry point ───────────────────────────────────────────────────── *)

let run ~scope tu_env members =
  let exprs = check_constant_exprs ~scope tu_env members in
  let undef = check_undef_constants ~scope ~root_env:tu_env tu_env members in
  let spec_locs = check_spec_locs ~scope members in
  let defs = check_definitions ~scope tu_env members in
  let type_defs = check_type_def ~scope tu_env members in
  let displayable = check_displayable_defs ~scope members in
  exprs @ undef @ spec_locs @ defs @ type_defs @ displayable

(** Shared types and utilities for translation-unit-level checks.

    Provides the TU environment type, symbol resolution, expression evaluation,
    and other helpers used across the TU check modules. This module is internal
    to the [fpp] library. *)

open Check_env

(* ── Symbol kinds ──────────────────────────────────────────────────── *)

type symbol_kind =
  | Sk_type
  | Sk_constant
  | Sk_port
  | Sk_component
  | Sk_instance
  | Sk_topology
  | Sk_state_machine
  | Sk_module
  | Sk_interface

let string_of_symbol_kind = function
  | Sk_type -> "type"
  | Sk_constant -> "constant"
  | Sk_port -> "port"
  | Sk_component -> "component"
  | Sk_instance -> "component instance"
  | Sk_topology -> "topology"
  | Sk_state_machine -> "state machine"
  | Sk_module -> "module"
  | Sk_interface -> "interface"

(* ── TU environment ────────────────────────────────────────────────── *)

type tu_env = {
  symbols : (symbol_kind * Ast.loc) SMap.t;
  modules : tu_env SMap.t;
  components : Ast.def_component SMap.t;
  port_defs : Ast.def_port SMap.t;
  interfaces : Ast.def_interface SMap.t;
  topologies : Ast.def_topology SMap.t;
  instances : Ast.def_component_instance SMap.t;
  state_machines : Ast.def_state_machine SMap.t;
  constants : Ast.def_constant SMap.t;
  types : (symbol_kind * Ast.loc) SMap.t;
  alias_targets : Ast.type_name Ast.node SMap.t;
}

let empty_tu_env =
  {
    symbols = SMap.empty;
    modules = SMap.empty;
    components = SMap.empty;
    port_defs = SMap.empty;
    interfaces = SMap.empty;
    topologies = SMap.empty;
    instances = SMap.empty;
    state_machines = SMap.empty;
    constants = SMap.empty;
    types = SMap.empty;
    alias_targets = SMap.empty;
  }

(* ── Build TU environment ──────────────────────────────────────────── *)

let add_symbol env name kind loc =
  { env with symbols = SMap.add name (kind, loc) env.symbols }

let rec build_tu_env members =
  List.fold_left
    (fun env ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_abs_type t ->
          let name = t.abs_name.data in
          let loc = t.abs_name.loc in
          let env = add_symbol env name Sk_type loc in
          { env with types = SMap.add name (Sk_type, loc) env.types }
      | Ast.Mod_def_alias_type t ->
          let name = t.alias_name.data in
          let loc = t.alias_name.loc in
          let env = add_symbol env name Sk_type loc in
          {
            env with
            types = SMap.add name (Sk_type, loc) env.types;
            alias_targets = SMap.add name t.alias_type env.alias_targets;
          }
      | Ast.Mod_def_array a ->
          let name = a.array_name.data in
          let loc = a.array_name.loc in
          let env = add_symbol env name Sk_type loc in
          { env with types = SMap.add name (Sk_type, loc) env.types }
      | Ast.Mod_def_enum e ->
          let name = e.enum_name.data in
          let loc = e.enum_name.loc in
          let env = add_symbol env name Sk_type loc in
          { env with types = SMap.add name (Sk_type, loc) env.types }
      | Ast.Mod_def_struct s ->
          let name = s.struct_name.data in
          let loc = s.struct_name.loc in
          let env = add_symbol env name Sk_type loc in
          { env with types = SMap.add name (Sk_type, loc) env.types }
      | Ast.Mod_def_constant c ->
          let name = c.const_name.data in
          let loc = c.const_name.loc in
          let env = add_symbol env name Sk_constant loc in
          { env with constants = SMap.add name c env.constants }
      | Ast.Mod_def_port p ->
          let name = p.port_name.data in
          let loc = p.port_name.loc in
          let env = add_symbol env name Sk_port loc in
          { env with port_defs = SMap.add name p env.port_defs }
      | Ast.Mod_def_component c ->
          let name = c.comp_name.data in
          let loc = c.comp_name.loc in
          let env = add_symbol env name Sk_component loc in
          { env with components = SMap.add name c env.components }
      | Ast.Mod_def_component_instance i ->
          let name = i.inst_name.data in
          let loc = i.inst_name.loc in
          let env = add_symbol env name Sk_instance loc in
          { env with instances = SMap.add name i env.instances }
      | Ast.Mod_def_topology t ->
          let name = t.topo_name.data in
          let loc = t.topo_name.loc in
          let env = add_symbol env name Sk_topology loc in
          { env with topologies = SMap.add name t env.topologies }
      | Ast.Mod_def_state_machine sm ->
          let name = sm.sm_name.data in
          let loc = sm.sm_name.loc in
          let env = add_symbol env name Sk_state_machine loc in
          { env with state_machines = SMap.add name sm env.state_machines }
      | Ast.Mod_def_module m ->
          let name = m.module_name.data in
          let loc = m.module_name.loc in
          let env = add_symbol env name Sk_module loc in
          let sub = build_tu_env m.module_members in
          { env with modules = SMap.add name sub env.modules }
      | Ast.Mod_def_interface i ->
          let name = i.intf_name.data in
          let loc = i.intf_name.loc in
          let env = add_symbol env name Sk_interface loc in
          { env with interfaces = SMap.add name i env.interfaces }
      | Ast.Mod_spec_loc _ | Ast.Mod_spec_include _ -> env)
    empty_tu_env members

let overlay_env ~parent ~child =
  let u _ _ c = Some c in
  {
    symbols = SMap.union u parent.symbols child.symbols;
    modules = SMap.union u parent.modules child.modules;
    components = SMap.union u parent.components child.components;
    port_defs = SMap.union u parent.port_defs child.port_defs;
    interfaces = SMap.union u parent.interfaces child.interfaces;
    topologies = SMap.union u parent.topologies child.topologies;
    instances = SMap.union u parent.instances child.instances;
    state_machines = SMap.union u parent.state_machines child.state_machines;
    constants = SMap.union u parent.constants child.constants;
    types = SMap.union u parent.types child.types;
    alias_targets = SMap.union u parent.alias_targets child.alias_targets;
  }

(* ── Symbol resolution ─────────────────────────────────────────────── *)

let resolve_symbol tu_env (qi : Ast.qual_ident) =
  let ids = Ast.qual_ident_to_list qi in
  match ids with
  | [] -> None
  | [ id ] -> SMap.find_opt id.Ast.data tu_env.symbols
  | _ ->
      let rec walk env = function
        | [] -> None
        | [ id ] -> SMap.find_opt id.Ast.data env.symbols
        | id :: rest -> (
            match SMap.find_opt id.Ast.data env.modules with
            | Some sub -> walk sub rest
            | None -> None)
      in
      walk tu_env ids

let article kind =
  match (string_of_symbol_kind kind).[0] with
  | 'a' | 'e' | 'i' | 'o' | 'u' -> "an"
  | _ -> "a"

let check_symbol_as_type ~scope tu_env (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some (Sk_type, _) -> []
  | Some (Sk_module, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is a module, not a type"
             (Ast.qual_ident_to_string qi.data));
      ]
  | Some (Sk_constant, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is a constant, not a type"
             (Ast.qual_ident_to_string qi.data));
      ]
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a type"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None -> []

let check_symbol_as_constant ~scope tu_env (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some (Sk_constant, _) -> []
  | Some (Sk_type, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is a type, not a constant"
             (Ast.qual_ident_to_string qi.data));
      ]
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a constant"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None -> []

let check_symbol_as_component ~scope tu_env (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some (Sk_component, _) -> []
  | Some (Sk_module, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is a module, not a component"
             (Ast.qual_ident_to_string qi.data));
      ]
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a component"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "undefined component '%s'"
             (Ast.qual_ident_to_string qi.data));
      ]

let check_symbol_as_topology ~scope tu_env (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some (Sk_topology, _) -> []
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a topology"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "undefined topology '%s'" (Ast.qual_ident_to_string qi.data));
      ]

let is_builtin_port (qi : Ast.qual_ident) =
  match qi with Ast.Unqualified id -> id.data = "serial" | _ -> false

let check_symbol_as_port ~scope tu_env (qi : Ast.qual_ident Ast.node) =
  if is_builtin_port qi.data then []
  else
    match resolve_symbol tu_env qi.data with
    | Some (Sk_port, _) -> []
    | Some (Sk_module, _) ->
        [
          error ~sm_name:scope qi.loc
            (Fmt.str "'%s' is a module, not a port"
               (Ast.qual_ident_to_string qi.data));
        ]
    | Some (kind, _) ->
        [
          error ~sm_name:scope qi.loc
            (Fmt.str "'%s' is %s %s, not a port"
               (Ast.qual_ident_to_string qi.data)
               (article kind)
               (string_of_symbol_kind kind));
        ]
    | None ->
        [
          error ~sm_name:scope qi.loc
            (Fmt.str "undefined port '%s'" (Ast.qual_ident_to_string qi.data));
        ]

let check_symbol_as_state_machine ~scope tu_env (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some (Sk_state_machine, _) -> []
  | Some (Sk_module, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is a module, not a state machine"
             (Ast.qual_ident_to_string qi.data));
      ]
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a state machine"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "undefined state machine '%s'"
             (Ast.qual_ident_to_string qi.data));
      ]

let check_symbol_as_instance ~scope tu_env (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some (Sk_instance, _) -> []
  | Some (Sk_module, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is a module, not a component instance"
             (Ast.qual_ident_to_string qi.data));
      ]
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a component instance"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None -> []

let check_type_name ~scope tu_env (tn : Ast.type_name Ast.node) =
  match tn.data with
  | Ast.Type_qual qi -> check_symbol_as_type ~scope tu_env qi
  | _ -> []

(* ── Expression evaluation ─────────────────────────────────────────── *)

type eval_result =
  | Val_int of int
  | Val_float of float
  | Val_string of string
  | Val_bool of bool
  | Val_array of eval_result list
  | Val_struct of (string * eval_result) list
  | Val_unknown

let eval_dot_access ~scope expr_loc v field diags =
  match v with
  | Val_struct members -> (
      match List.assoc_opt field.Ast.data members with
      | Some v -> (v, diags)
      | None ->
          ( Val_unknown,
            diags
            @ [
                error ~sm_name:scope field.loc
                  (Fmt.str "struct has no member '%s'" field.data);
              ] ))
  | Val_int _ | Val_float _ | Val_string _ | Val_bool _ ->
      ( Val_unknown,
        diags
        @ [
            error ~sm_name:scope expr_loc
              "cannot access member of non-struct expression";
          ] )
  | _ -> (Val_unknown, diags)

let eval_subscript_access ~scope arr_val idx_val arr_loc idx_loc diags =
  match idx_val with
  | Val_bool _ | Val_string _ ->
      ( Val_unknown,
        diags
        @ [
            error ~sm_name:scope idx_loc
              "array index must be a numeric expression";
          ] )
  | Val_int n -> (
      match arr_val with
      | Val_array elts ->
          if n < 0 then
            ( Val_unknown,
              diags
              @ [
                  error ~sm_name:scope idx_loc
                    (Fmt.str "array index %d is negative" n);
                ] )
          else if n >= List.length elts then
            ( Val_unknown,
              diags
              @ [
                  error ~sm_name:scope idx_loc
                    (Fmt.str "array index %d is out of bounds (length %d)" n
                       (List.length elts));
                ] )
          else (List.nth elts n, diags)
      | Val_struct _ ->
          ( Val_unknown,
            diags
            @ [
                error ~sm_name:scope arr_loc "cannot index a struct expression";
              ] )
      | _ -> (Val_unknown, diags))
  | _ -> (Val_unknown, diags)

let eval_visiting = Hashtbl.create 16

let rec eval_expr ~scope tu_env (e : Ast.expr Ast.node) =
  match e.data with
  | Ast.Expr_literal (Ast.Lit_int s) -> (
      match int_of_string_opt s with
      | Some n -> (Val_int n, [])
      | None ->
          ( Val_unknown,
            [
              error ~sm_name:scope e.loc
                (Fmt.str "integer literal '%s' out of range" s);
            ] ))
  | Ast.Expr_literal (Ast.Lit_float s) -> (
      match float_of_string_opt s with
      | Some f -> (Val_float f, [])
      | None -> (Val_unknown, []))
  | Ast.Expr_literal (Ast.Lit_string s) -> (Val_string s, [])
  | Ast.Expr_literal (Ast.Lit_bool b) -> (Val_bool b, [])
  | Ast.Expr_paren inner -> eval_expr ~scope tu_env inner
  | Ast.Expr_unop (Ast.Minus, inner) -> (
      let v, diags = eval_expr ~scope tu_env inner in
      match v with
      | Val_int n -> (Val_int (-n), diags)
      | Val_float f -> (Val_float (-.f), diags)
      | Val_struct _ | Val_array _ ->
          ( Val_unknown,
            diags
            @ [
                error ~sm_name:scope e.loc
                  "cannot negate a struct or array expression";
              ] )
      | _ -> (Val_unknown, diags))
  | Ast.Expr_binop (l, op, r) ->
      let lv, ld = eval_expr ~scope tu_env l in
      let rv, rd = eval_expr ~scope tu_env r in
      let diags = ld @ rd in
      eval_binop ~scope e.loc op lv rv diags
  | Ast.Expr_ident id -> (
      match SMap.find_opt id.data tu_env.constants with
      | Some c ->
          if Hashtbl.mem eval_visiting id.data then (Val_unknown, [])
          else (
            Hashtbl.replace eval_visiting id.data true;
            let v, _ = eval_expr ~scope tu_env c.const_value in
            Hashtbl.remove eval_visiting id.data;
            (v, []))
      | None -> (Val_unknown, []))
  | Ast.Expr_array es ->
      let vals =
        List.map
          (fun e ->
            let v, _ = eval_expr ~scope tu_env e in
            v)
          es
      in
      (Val_array vals, [])
  | Ast.Expr_struct ms ->
      let vals =
        List.map
          (fun (m : Ast.struct_member Ast.node) ->
            let v, _ = eval_expr ~scope tu_env m.data.sm_value in
            (m.data.sm_name.data, v))
          ms
      in
      (Val_struct vals, [])
  | Ast.Expr_dot (inner, field) ->
      eval_qual_or_dot ~scope tu_env e.loc inner field
  | Ast.Expr_subscript (arr, idx) ->
      let av, ad = eval_expr ~scope tu_env arr in
      let iv, id = eval_expr ~scope tu_env idx in
      eval_subscript_access ~scope av iv arr.loc idx.loc (ad @ id)

and eval_qual_or_dot ~scope tu_env loc inner field =
  (* Try qualified constant resolution first (e.g. M.a) *)
  let rec expr_ids (e : Ast.expr Ast.node) =
    match e.data with
    | Ast.Expr_ident id -> Some [ id ]
    | Ast.Expr_dot (inner, f) -> (
        match expr_ids inner with
        | Some ids -> Some (ids @ [ f ])
        | None -> None)
    | _ -> None
  in
  let rec walk_mods env = function
    | [] -> None
    | [ last ] -> (
        match SMap.find_opt last.Ast.data env.constants with
        | Some c ->
            let key = last.data in
            if Hashtbl.mem eval_visiting key then Some (Val_unknown, [])
            else (
              Hashtbl.replace eval_visiting key true;
              let v, d = eval_expr ~scope env c.const_value in
              Hashtbl.remove eval_visiting key;
              Some (v, d))
        | None -> None)
    | id :: rest -> (
        match SMap.find_opt id.Ast.data env.modules with
        | Some sub -> walk_mods sub rest
        | None -> None)
  in
  let qual_result =
    match expr_ids inner with
    | Some ids -> walk_mods tu_env (ids @ [ field ])
    | None -> None
  in
  match qual_result with
  | Some r -> r
  | None ->
      let v, diags = eval_expr ~scope tu_env inner in
      eval_dot_access ~scope loc v field diags

and eval_binop ~scope loc op lv rv diags =
  match (lv, rv) with
  | Val_int a, Val_int b -> (
      match op with
      | Ast.Add -> (Val_int (a + b), diags)
      | Ast.Sub -> (Val_int (a - b), diags)
      | Ast.Mul -> (Val_int (a * b), diags)
      | Ast.Div ->
          if b = 0 then
            ( Val_unknown,
              diags
              @ [ error ~sm_name:scope loc "division by zero in constant" ] )
          else (Val_int (a / b), diags))
  | Val_float a, Val_float b -> (
      match op with
      | Ast.Add -> (Val_float (a +. b), diags)
      | Ast.Sub -> (Val_float (a -. b), diags)
      | Ast.Mul -> (Val_float (a *. b), diags)
      | Ast.Div -> (Val_float (a /. b), diags))
  | Val_int a, Val_float b -> (
      match op with
      | Ast.Add -> (Val_float (Float.of_int a +. b), diags)
      | Ast.Sub -> (Val_float (Float.of_int a -. b), diags)
      | Ast.Mul -> (Val_float (Float.of_int a *. b), diags)
      | Ast.Div -> (Val_float (Float.of_int a /. b), diags))
  | Val_float a, Val_int b -> (
      match op with
      | Ast.Add -> (Val_float (a +. Float.of_int b), diags)
      | Ast.Sub -> (Val_float (a -. Float.of_int b), diags)
      | Ast.Mul -> (Val_float (a *. Float.of_int b), diags)
      | Ast.Div ->
          if b = 0 then
            ( Val_unknown,
              diags
              @ [ error ~sm_name:scope loc "division by zero in constant" ] )
          else (Val_float (a /. Float.of_int b), diags))
  | Val_string _, _ | _, Val_string _ ->
      ( Val_unknown,
        diags
        @ [
            error ~sm_name:scope loc
              "invalid arithmetic operation on string type";
          ] )
  | _ -> (Val_unknown, diags)

let check_expr ~scope tu_env (e : Ast.expr Ast.node) =
  let _, diags = eval_expr ~scope tu_env e in
  diags

let check_numeric_expr ~scope tu_env (e : Ast.expr Ast.node) what =
  let v, diags = eval_expr ~scope tu_env e in
  match v with
  | Val_string _ ->
      diags
      @ [
          error ~sm_name:scope e.loc
            (Fmt.str "%s must be a numeric expression" what);
        ]
  | Val_bool _ ->
      diags
      @ [
          error ~sm_name:scope e.loc
            (Fmt.str "%s must be a numeric expression" what);
        ]
  | _ -> diags

let check_nonneg_id ~scope tu_env (e : Ast.expr Ast.node) what =
  let v, diags = eval_expr ~scope tu_env e in
  match v with
  | Val_int n when n < 0 ->
      diags
      @ [ error ~sm_name:scope e.loc (Fmt.str "%s must be non-negative" what) ]
  | Val_string _ ->
      diags
      @ [
          error ~sm_name:scope e.loc
            (Fmt.str "%s must be a numeric expression" what);
        ]
  | _ -> diags

let check_array_mixed_elements ~scope tu_env (es : Ast.expr Ast.node list) loc =
  let has_struct = ref false in
  let has_array = ref false in
  List.iter
    (fun e ->
      let v, _ = eval_expr ~scope tu_env e in
      match v with
      | Val_struct _ -> has_struct := true
      | Val_array _ -> has_array := true
      | _ -> ())
    es;
  if !has_struct && !has_array then
    [
      error ~sm_name:scope loc
        "array expression mixes struct and array elements";
    ]
  else []

let check_array_expr ~scope tu_env (e : Ast.expr Ast.node) =
  match e.data with
  | Ast.Expr_array [] -> [ error ~sm_name:scope e.loc "empty array expression" ]
  | Ast.Expr_array es ->
      let v_diags =
        let _, diags = eval_expr ~scope tu_env e in
        diags
      in
      v_diags @ check_array_mixed_elements ~scope tu_env es e.loc
  | Ast.Expr_struct _ ->
      let _, diags = eval_expr ~scope tu_env e in
      diags
  | _ ->
      let _, diags = eval_expr ~scope tu_env e in
      diags

let check_struct_expr_dupes ~scope (e : Ast.expr Ast.node) =
  match e.data with
  | Ast.Expr_struct ms ->
      let seen = Hashtbl.create 8 in
      let diags = ref [] in
      List.iter
        (fun (m : Ast.struct_member Ast.node) ->
          let name = m.data.sm_name.data in
          match Hashtbl.find_opt seen name with
          | Some _ ->
              diags :=
                error ~sm_name:scope m.data.sm_name.loc
                  (Fmt.str "duplicate member '%s' in struct expression" name)
                :: !diags
          | None -> Hashtbl.replace seen name true)
        ms;
      List.rev !diags
  | _ -> []

(* ── Type helpers ──────────────────────────────────────────────────── *)

let is_numeric_type = function
  | Ast.Type_int _ | Ast.Type_float _ -> true
  | _ -> false

let is_numeric_resolved_tu _tu_env (tn : Ast.type_name Ast.node) =
  match tn.data with
  | Ast.Type_int _ | Ast.Type_float _ -> true
  | Ast.Type_bool -> true
  | Ast.Type_qual _ ->
      (* Qualified types might alias numeric types; be conservative *)
      true
  | _ -> false

let is_integer_type (tn : Ast.type_name) =
  match tn with Ast.Type_int _ -> true | _ -> false

let is_integer_type_resolved tu_env (tn : Ast.type_name Ast.node) =
  let rec resolve visited (t : Ast.type_name) =
    match t with
    | Ast.Type_int _ -> true
    | Ast.Type_qual qi -> (
        let name =
          match qi.data with
          | Ast.Unqualified id -> id.data
          | _ -> Ast.qual_ident_to_string qi.data
        in
        if SSet.mem name visited then false
        else
          let visited = SSet.add name visited in
          match SMap.find_opt name tu_env.alias_targets with
          | Some target -> resolve visited target.data
          | None -> false)
    | _ -> false
  in
  resolve SSet.empty tn.data

let is_float_type (tn : Ast.type_name) =
  match tn with Ast.Type_float _ -> true | _ -> false

let is_float_type_resolved tu_env (tn : Ast.type_name Ast.node) =
  let rec resolve visited (t : Ast.type_name) =
    match t with
    | Ast.Type_float _ -> true
    | Ast.Type_qual qi -> (
        let name =
          match qi.data with
          | Ast.Unqualified id -> id.data
          | _ -> Ast.qual_ident_to_string qi.data
        in
        if SSet.mem name visited then false
        else
          let visited = SSet.add name visited in
          match SMap.find_opt name tu_env.alias_targets with
          | Some target -> resolve visited target.data
          | None -> false)
    | _ -> false
  in
  resolve SSet.empty tn.data

let count_format_repls s =
  let n = ref 0 in
  let i = ref 0 in
  let len = String.length s in
  while !i < len do
    if s.[!i] = '{' then (
      let j = ref (!i + 1) in
      while !j < len && s.[!j] <> '}' do
        incr j
      done;
      if !j < len then (
        incr n;
        i := !j + 1)
      else i := len)
    else incr i
  done;
  !n

type format_spec_kind = Fmt_default | Fmt_integer | Fmt_float of int option

let classify_format_spec spec =
  let len = String.length spec in
  if len = 0 then Fmt_default
  else
    let last = spec.[len - 1] in
    match last with
    | 'd' | 'x' | 'o' -> Fmt_integer
    | 'e' | 'f' | 'g' ->
        if len > 1 && spec.[0] = '.' then
          let prec_str = String.sub spec 1 (len - 2) in
          match int_of_string_opt prec_str with
          | Some n -> Fmt_float (Some n)
          | None -> Fmt_float None
        else Fmt_float None
    | _ -> Fmt_default

let extract_format_spec fmt =
  let len = String.length fmt in
  let rec scan i =
    if i >= len then Fmt_default
    else if fmt.[i] = '{' then (
      let j = ref (i + 1) in
      while !j < len && fmt.[!j] <> '}' do
        incr j
      done;
      if !j >= len then Fmt_default
      else
        let spec = String.sub fmt (i + 1) (!j - i - 1) in
        classify_format_spec spec)
    else scan (i + 1)
  in
  scan 0

let check_format_string ~scope loc (fmt : string) n_expected =
  let diags = ref [] in
  let n_repls = count_format_repls fmt in
  if n_repls <> n_expected then
    diags :=
      error ~sm_name:scope loc
        (Fmt.str "format string has %d replacement%s but expected %d" n_repls
           (if n_repls <> 1 then "s" else "")
           n_expected)
      :: !diags;
  let len = String.length fmt in
  let i = ref 0 in
  while !i < len do
    if fmt.[!i] = '{' then (
      let j = ref (!i + 1) in
      while !j < len && fmt.[!j] <> '}' do
        incr j
      done;
      if !j >= len then (
        diags :=
          error ~sm_name:scope loc "unclosed '{' in format string" :: !diags;
        i := len)
      else i := !j + 1)
    else incr i
  done;
  List.rev !diags

(* ── Component lookup ──────────────────────────────────────────────── *)

let resolve_in_env tu_env qi field =
  let name =
    match qi with
    | Ast.Unqualified id -> id.data
    | Ast.Qualified _ -> (
        let ids = Ast.qual_ident_to_list qi in
        match List.rev ids with last :: _ -> last.data | [] -> "")
  in
  match SMap.find_opt name (field tu_env) with
  | Some x -> Some x
  | None ->
      let ids = Ast.qual_ident_to_list qi in
      let rec walk env = function
        | [] -> None
        | [ id ] -> SMap.find_opt id.Ast.data (field env)
        | id :: rest -> (
            match SMap.find_opt id.Ast.data env.modules with
            | Some sub -> walk sub rest
            | None -> None)
      in
      walk tu_env ids

let component tu_env (qi : Ast.qual_ident Ast.node) =
  resolve_in_env tu_env qi.data (fun env -> env.components)

let interface tu_env (qi : Ast.qual_ident) =
  resolve_in_env tu_env qi (fun env -> env.interfaces)

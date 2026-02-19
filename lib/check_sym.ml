(** Symbol kind validation and dependency cycle detection.

    Checks that referenced symbols have the expected kind (type, constant,
    component, etc.) and detects definition cycles. This module is internal to
    the [fpp] library. *)

open Check_env
open Check_tu_env

(* ── Symbol kind checks ───────────────────────────────────────────── *)

let article kind =
  match (string_of_symbol_kind kind).[0] with
  | 'a' | 'e' | 'i' | 'o' | 'u' -> "an"
  | _ -> "a"

let resolve_in ~tu_env ~root_env (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some _ as r -> r
  | None -> resolve_symbol root_env qi.data

let check_as_type_with_root ~scope tu_env root_env
    (qi : Ast.qual_ident Ast.node) =
  match resolve_in ~tu_env ~root_env qi with
  | Some (Sk_type, _) -> []
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a type"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None -> []

let check_as_constant_with_root ~scope tu_env root_env
    (qi : Ast.qual_ident Ast.node) =
  match resolve_in ~tu_env ~root_env qi with
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

let check_as_component_with_root ~scope tu_env root_env
    (qi : Ast.qual_ident Ast.node) =
  match resolve_in ~tu_env ~root_env qi with
  | Some (Sk_component, _) -> []
  | Some (kind, _) ->
      [
        error ~sm_name:scope qi.loc
          (Fmt.str "'%s' is %s %s, not a component"
             (Ast.qual_ident_to_string qi.data)
             (article kind)
             (string_of_symbol_kind kind));
      ]
  | None -> []

let check_type_name_with_root ~scope tu_env root_env
    (tn : Ast.type_name Ast.node) =
  match tn.data with
  | Ast.Type_qual qi -> check_as_type_with_root ~scope tu_env root_env qi
  | _ -> []

let rec check_symbol_kinds ~scope ~root_env tu_env members =
  List.concat_map
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_alias_type t ->
          check_type_name_with_root ~scope tu_env root_env t.alias_type
      | Ast.Mod_def_array a ->
          check_type_name_with_root ~scope tu_env root_env a.array_elt_type
      | Ast.Mod_def_enum e -> (
          match e.enum_type with
          | Some t -> check_type_name_with_root ~scope tu_env root_env t
          | None -> [])
      | Ast.Mod_def_struct s ->
          List.concat_map
            (fun ann ->
              let m : Ast.struct_type_member = (Ast.unannotate ann).Ast.data in
              check_type_name_with_root ~scope tu_env root_env m.struct_mem_type)
            s.struct_members
      | Ast.Mod_def_port p -> (
          List.concat_map
            (fun ann ->
              let fp : Ast.formal_param = (Ast.unannotate ann).Ast.data in
              check_type_name_with_root ~scope tu_env root_env fp.fp_type)
            p.port_params
          @
          match p.port_return with
          | Some t -> check_type_name_with_root ~scope tu_env root_env t
          | None -> [])
      | Ast.Mod_def_constant c ->
          check_expr_symbol_kinds ~scope ~root_env tu_env c.const_value
      | Ast.Mod_def_component_instance i ->
          check_as_component_with_root ~scope tu_env root_env i.inst_component
      | Ast.Mod_def_module m ->
          let sub_env =
            match SMap.find_opt m.module_name.data tu_env.modules with
            | Some e -> e
            | None -> tu_env
          in
          check_symbol_kinds
            ~scope:(scope ^ "." ^ m.module_name.data)
            ~root_env sub_env m.module_members
      | _ -> [])
    members

and check_expr_symbol_kinds ~scope ~root_env tu_env (e : Ast.expr Ast.node) =
  match e.data with
  | Ast.Expr_ident id ->
      let qi = Ast.node id.loc (Ast.Unqualified id) in
      check_as_constant_with_root ~scope tu_env root_env qi
  | Ast.Expr_paren inner ->
      check_expr_symbol_kinds ~scope ~root_env tu_env inner
  | Ast.Expr_unop (_, inner) ->
      check_expr_symbol_kinds ~scope ~root_env tu_env inner
  | Ast.Expr_binop (l, _, r) ->
      check_expr_symbol_kinds ~scope ~root_env tu_env l
      @ check_expr_symbol_kinds ~scope ~root_env tu_env r
  | _ -> []

(* ── Dependency cycle detection ────────────────────────────────────── *)

let rec expr_refs (e : Ast.expr Ast.node) =
  match e.data with
  | Ast.Expr_ident id -> [ id.data ]
  | Ast.Expr_literal _ -> []
  | Ast.Expr_paren inner -> expr_refs inner
  | Ast.Expr_unop (_, inner) -> expr_refs inner
  | Ast.Expr_binop (l, _, r) -> expr_refs l @ expr_refs r
  | Ast.Expr_array es -> List.concat_map expr_refs es
  | Ast.Expr_struct ms ->
      List.concat_map
        (fun (m : Ast.struct_member Ast.node) -> expr_refs m.data.sm_value)
        ms
  | Ast.Expr_dot (e, _) -> expr_refs e
  | Ast.Expr_subscript (e1, e2) -> expr_refs e1 @ expr_refs e2

let type_name_ref (tn : Ast.type_name Ast.node) =
  match tn.data with
  | Ast.Type_qual qi -> (
      match qi.data with Ast.Unqualified id -> Some id.data | _ -> None)
  | _ -> None

let register_def_deps graph locs (n : Ast.module_member Ast.node) =
  match n.Ast.data with
  | Ast.Mod_def_constant c ->
      Hashtbl.replace locs c.const_name.data c.const_name.loc;
      Hashtbl.replace graph c.const_name.data (expr_refs c.const_value)
  | Ast.Mod_def_alias_type t ->
      let name = t.alias_name.data in
      Hashtbl.replace locs name t.alias_name.loc;
      let deps =
        match type_name_ref t.alias_type with Some r -> [ r ] | None -> []
      in
      Hashtbl.replace graph name deps
  | Ast.Mod_def_array a ->
      let name = a.array_name.data in
      Hashtbl.replace locs name a.array_name.loc;
      let deps =
        match type_name_ref a.array_elt_type with Some r -> [ r ] | None -> []
      in
      Hashtbl.replace graph name deps
  | Ast.Mod_def_struct s ->
      let name = s.struct_name.data in
      Hashtbl.replace locs name s.struct_name.loc;
      let deps =
        List.filter_map
          (fun ann ->
            let m : Ast.struct_type_member = (Ast.unannotate ann).Ast.data in
            type_name_ref m.struct_mem_type)
          s.struct_members
      in
      Hashtbl.replace graph name deps
  | Ast.Mod_def_enum e ->
      let name = e.enum_name.data in
      Hashtbl.replace locs name e.enum_name.loc;
      let type_deps =
        match e.enum_type with
        | Some t -> ( match type_name_ref t with Some r -> [ r ] | None -> [])
        | None -> []
      in
      let const_deps =
        List.concat_map
          (fun ann ->
            let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
            match c.enum_const_value with Some e -> expr_refs e | None -> [])
          e.enum_constants
      in
      Hashtbl.replace graph name (type_deps @ const_deps)
  | _ -> ()

let build_dep_graph members =
  let graph = Hashtbl.create 32 in
  let locs = Hashtbl.create 32 in
  let rec walk members =
    List.iter
      (fun ann ->
        let n = Ast.unannotate ann in
        match n.Ast.data with
        | Ast.Mod_def_module m -> walk m.module_members
        | _ -> register_def_deps graph locs n)
      members
  in
  walk members;
  (graph, locs)

let check_cycles ~scope members =
  let graph, locs = build_dep_graph members in
  let visited = Hashtbl.create 32 in
  let in_stack = Hashtbl.create 32 in
  let diags = ref [] in
  let rec dfs node =
    if Hashtbl.mem in_stack node then
      let loc =
        match Hashtbl.find_opt locs node with
        | Some l -> l
        | None -> Ast.dummy_loc
      in
      diags :=
        error ~sm_name:scope loc
          (Fmt.str "definition '%s' is part of a dependency cycle" node)
        :: !diags
    else if not (Hashtbl.mem visited node) then (
      Hashtbl.replace visited node true;
      Hashtbl.replace in_stack node true;
      (match Hashtbl.find_opt graph node with
      | Some deps ->
          List.iter (fun dep -> if Hashtbl.mem graph dep then dfs dep) deps
      | None -> ());
      Hashtbl.remove in_stack node)
  in
  Hashtbl.iter (fun name _ -> dfs name) graph;
  !diags

(* ── Entry point ───────────────────────────────────────────────────── *)

let run ~scope tu_env members =
  let sym_kinds = check_symbol_kinds ~scope ~root_env:tu_env tu_env members in
  let cycles = check_cycles ~scope members in
  sym_kinds @ cycles

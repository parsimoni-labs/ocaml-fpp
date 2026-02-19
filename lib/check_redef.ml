(** Redefinition detection for TU-level definitions.

    Detects duplicate declarations at each scope level: modules, components,
    enums, structs. This module is internal to the [fpp] library. *)

open Check_env

(* ── Scope-level duplicate checks ─────────────────────────────────── *)

let check_redefs_in_scope ~scope members =
  let seen = Hashtbl.create 16 in
  let diags = ref [] in
  let add name loc =
    match Hashtbl.find_opt seen name with
    | Some prev_loc ->
        diags :=
          error ~sm_name:scope loc
            (Fmt.str "duplicate definition '%s' (first defined at %s:%d:%d)"
               name prev_loc.Ast.file prev_loc.line prev_loc.col)
          :: !diags
    | None -> Hashtbl.replace seen name loc
  in
  List.iter
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Mod_def_abs_type t -> add t.abs_name.data t.abs_name.loc
      | Ast.Mod_def_alias_type t -> add t.alias_name.data t.alias_name.loc
      | Ast.Mod_def_array a -> add a.array_name.data a.array_name.loc
      | Ast.Mod_def_enum e -> add e.enum_name.data e.enum_name.loc
      | Ast.Mod_def_struct s -> add s.struct_name.data s.struct_name.loc
      | Ast.Mod_def_constant c -> add c.const_name.data c.const_name.loc
      | Ast.Mod_def_port p -> add p.port_name.data p.port_name.loc
      | Ast.Mod_def_component c -> add c.comp_name.data c.comp_name.loc
      | Ast.Mod_def_component_instance i -> add i.inst_name.data i.inst_name.loc
      | Ast.Mod_def_topology t -> add t.topo_name.data t.topo_name.loc
      | Ast.Mod_def_state_machine sm -> add sm.sm_name.data sm.sm_name.loc
      | Ast.Mod_def_module m -> add m.module_name.data m.module_name.loc
      | Ast.Mod_def_interface i -> add i.intf_name.data i.intf_name.loc
      | Ast.Mod_spec_loc _ | Ast.Mod_spec_include _ -> ())
    members;
  List.rev !diags

let check_enum_constant_redefs ~scope (e : Ast.def_enum) =
  let seen = Hashtbl.create 8 in
  let diags = ref [] in
  List.iter
    (fun ann ->
      let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
      let name = c.enum_const_name.data in
      let loc = c.enum_const_name.loc in
      match Hashtbl.find_opt seen name with
      | Some prev_loc ->
          diags :=
            error ~sm_name:scope loc
              (Fmt.str
                 "duplicate enum constant '%s' (first defined at %s:%d:%d)" name
                 prev_loc.Ast.file prev_loc.line prev_loc.col)
            :: !diags
      | None -> Hashtbl.replace seen name loc)
    e.enum_constants;
  List.rev !diags

let check_struct_member_redefs ~scope (s : Ast.def_struct) =
  let seen = Hashtbl.create 8 in
  let diags = ref [] in
  List.iter
    (fun ann ->
      let m : Ast.struct_type_member = (Ast.unannotate ann).Ast.data in
      let name = m.struct_mem_name.data in
      let loc = m.struct_mem_name.loc in
      match Hashtbl.find_opt seen name with
      | Some prev_loc ->
          diags :=
            error ~sm_name:scope loc
              (Fmt.str
                 "duplicate struct member '%s' (first defined at %s:%d:%d)" name
                 prev_loc.Ast.file prev_loc.line prev_loc.col)
            :: !diags
      | None -> Hashtbl.replace seen name loc)
    s.struct_members;
  List.rev !diags

let check_component_member_redefs ~scope (comp : Ast.def_component) =
  let seen = Hashtbl.create 16 in
  let diags = ref [] in
  let add name loc =
    match Hashtbl.find_opt seen name with
    | Some prev_loc ->
        diags :=
          error ~sm_name:scope loc
            (Fmt.str "duplicate definition '%s' (first defined at %s:%d:%d)"
               name prev_loc.Ast.file prev_loc.line prev_loc.col)
          :: !diags
    | None -> Hashtbl.replace seen name loc
  in
  List.iter
    (fun ann ->
      let n = Ast.unannotate ann in
      match n.Ast.data with
      | Ast.Comp_def_abs_type t -> add t.abs_name.data t.abs_name.loc
      | Ast.Comp_def_alias_type t -> add t.alias_name.data t.alias_name.loc
      | Ast.Comp_def_array a -> add a.array_name.data a.array_name.loc
      | Ast.Comp_def_enum e -> add e.enum_name.data e.enum_name.loc
      | Ast.Comp_def_struct s -> add s.struct_name.data s.struct_name.loc
      | Ast.Comp_def_constant c -> add c.const_name.data c.const_name.loc
      | Ast.Comp_def_state_machine sm -> add sm.sm_name.data sm.sm_name.loc
      | Ast.Comp_spec_command cmd -> add cmd.cmd_name.data cmd.cmd_name.loc
      | Ast.Comp_spec_event ev -> add ev.event_name.data ev.event_name.loc
      | Ast.Comp_spec_param p -> add p.param_name.data p.param_name.loc
      | Ast.Comp_spec_tlm_channel t -> add t.tlm_name.data t.tlm_name.loc
      | Ast.Comp_spec_container c ->
          add ("container:" ^ c.container_name.data) c.container_name.loc
      | Ast.Comp_spec_record r ->
          add ("record:" ^ r.record_name.data) r.record_name.loc
      | Ast.Comp_spec_port_instance (Port_general g) ->
          add g.gen_name.data g.gen_name.loc
      | Ast.Comp_spec_port_instance (Port_special s) ->
          add s.special_name.data s.special_name.loc
      | Ast.Comp_spec_internal_port ip ->
          add ip.internal_name.data ip.internal_name.loc
      | Ast.Comp_spec_sm_instance smi -> add smi.smi_name.data smi.smi_name.loc
      | Ast.Comp_spec_port_matching _ | Ast.Comp_spec_include _
      | Ast.Comp_spec_import_interface _ ->
          ())
    comp.comp_members;
  List.rev !diags

(* ── Recursive TU traversal ───────────────────────────────────────── *)

let rec check_redefinitions ~scope members =
  let self = check_redefs_in_scope ~scope members in
  let nested =
    List.concat_map
      (fun ann ->
        let n = Ast.unannotate ann in
        match n.Ast.data with
        | Ast.Mod_def_module m ->
            let scope = scope ^ "." ^ m.module_name.data in
            check_redefinitions ~scope m.module_members
        | Ast.Mod_def_component c ->
            let scope = scope ^ "." ^ c.comp_name.data in
            check_component_member_redefs ~scope c
        | Ast.Mod_def_enum e -> check_enum_constant_redefs ~scope e
        | Ast.Mod_def_struct s -> check_struct_member_redefs ~scope s
        | _ -> [])
      members
  in
  self @ nested

(* ── Entry point ───────────────────────────────────────────────────── *)

let run ~scope members = check_redefinitions ~scope members

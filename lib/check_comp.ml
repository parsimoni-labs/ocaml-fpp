(** Component member validation.

    Validates all aspects of component definitions: port requirements, member
    IDs, duplicate detection, type references, and special port constraints.
    Also validates port definitions and interface definitions. This module is
    internal to the [fpp] library. *)

open Check_env
open Check_tu_env

(* ── Component member predicates ──────────────────────────────────── *)

let interface_has_async_input tu_env (intf_name : Ast.qual_ident) =
  let name =
    match intf_name with
    | Ast.Unqualified id -> id.data
    | _ -> Ast.qual_ident_to_string intf_name
  in
  match SMap.find_opt name tu_env.interfaces with
  | Some intf ->
      List.exists
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Intf_spec_port_instance (Port_general g) ->
              g.gen_kind = Async_input
          | _ -> false)
        intf.intf_members
  | None -> false

let has_async_input tu_env (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_general g) -> g.gen_kind = Async_input
      | Ast.Comp_spec_port_instance (Port_special s) -> (
          match s.special_input_kind with Some Async -> true | _ -> false)
      | Ast.Comp_spec_internal_port _ -> true
      | Ast.Comp_spec_command c -> c.cmd_kind = Command_async
      | Ast.Comp_spec_sm_instance _ -> true
      | Ast.Comp_spec_import_interface ii ->
          interface_has_async_input tu_env ii.data
      | _ -> false)
    comp.comp_members

let has_special_port kind (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_special s) -> s.special_kind = kind
      | _ -> false)
    comp.comp_members

let has_commands (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_command _ -> true
      | _ -> false)
    comp.comp_members

let has_events (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_event _ -> true
      | _ -> false)
    comp.comp_members

let has_params (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_param _ -> true
      | _ -> false)
    comp.comp_members

let has_telemetry (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_tlm_channel _ -> true
      | _ -> false)
    comp.comp_members

let has_containers (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_container _ -> true
      | _ -> false)
    comp.comp_members

let has_records (comp : Ast.def_component) =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_record _ -> true
      | _ -> false)
    comp.comp_members

(* ── Component-local type environment ─────────────────────────────── *)

let build_comp_types (comp : Ast.def_component) =
  let types = Hashtbl.create 8 in
  let constants = Hashtbl.create 8 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_def_abs_type t -> Hashtbl.replace types t.abs_name.data true
      | Ast.Comp_def_alias_type t ->
          Hashtbl.replace types t.alias_name.data true
      | Ast.Comp_def_array a -> Hashtbl.replace types a.array_name.data true
      | Ast.Comp_def_enum e ->
          Hashtbl.replace types e.enum_name.data true;
          List.iter
            (fun ann ->
              let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
              Hashtbl.replace constants c.enum_const_name.data true)
            e.enum_constants
      | Ast.Comp_def_struct s -> Hashtbl.replace types s.struct_name.data true
      | Ast.Comp_def_constant c ->
          Hashtbl.replace constants c.const_name.data true
      | _ -> ())
    comp.comp_members;
  (types, constants)

(* ── Port type checks ─────────────────────────────────────────────── *)

let check_async_port_type ~scope tu_env (qi : Ast.qual_ident Ast.node) port_name
    =
  let name =
    match qi.data with
    | Ast.Unqualified id -> id.data
    | _ -> Ast.qual_ident_to_string qi.data
  in
  let port_def =
    match SMap.find_opt name tu_env.port_defs with
    | Some p -> Some p
    | None ->
        let ids = Ast.qual_ident_to_list qi.data in
        let rec walk env = function
          | [] -> None
          | [ id ] -> SMap.find_opt id.Ast.data env.port_defs
          | id :: rest -> (
              match SMap.find_opt id.Ast.data env.modules with
              | Some sub -> walk sub rest
              | None -> None)
        in
        walk tu_env ids
  in
  match port_def with
  | Some p -> (
      match p.port_return with
      | Some _ ->
          [
            error ~sm_name:scope qi.loc
              (Fmt.str "async input port '%s' cannot have return type" port_name);
          ]
      | None -> [])
  | None -> []

let check_internal_port_params ~scope (ip : Ast.spec_internal_port) =
  let diags = ref [] in
  List.iter
    (fun ann ->
      let fp : Ast.formal_param = (Ast.unannotate ann).Ast.data in
      if fp.fp_kind = Param_ref then
        diags :=
          error ~sm_name:scope fp.fp_name.loc
            (Fmt.str "internal port '%s' cannot have ref parameters"
               ip.internal_name.data)
          :: !diags)
    ip.internal_params;
  let seen = Hashtbl.create 4 in
  List.iter
    (fun ann ->
      let fp : Ast.formal_param = (Ast.unannotate ann).Ast.data in
      let name = fp.fp_name.data in
      match Hashtbl.find_opt seen name with
      | Some prev_loc ->
          diags :=
            error ~sm_name:scope fp.fp_name.loc
              (Fmt.str "duplicate parameter '%s' (first at %s:%d:%d)" name
                 prev_loc.Ast.file prev_loc.line prev_loc.col)
            :: !diags
      | None -> Hashtbl.replace seen name fp.fp_name.loc)
    ip.internal_params;
  List.rev !diags

let check_command_params ~scope (cmd : Ast.spec_command) =
  let diags = ref [] in
  let seen = Hashtbl.create 4 in
  List.iter
    (fun ann ->
      let fp : Ast.formal_param = (Ast.unannotate ann).Ast.data in
      let name = fp.fp_name.data in
      match Hashtbl.find_opt seen name with
      | Some prev_loc ->
          diags :=
            error ~sm_name:scope fp.fp_name.loc
              (Fmt.str "duplicate parameter '%s' (first at %s:%d:%d)" name
                 prev_loc.Ast.file prev_loc.line prev_loc.col)
            :: !diags
      | None -> Hashtbl.replace seen name fp.fp_name.loc)
    cmd.cmd_params;
  List.rev !diags

(* ── Interface deep async check ───────────────────────────────────── *)

let rec interface_has_async_input_deep tu_env visited (intf : Ast.def_interface)
    =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Intf_spec_port_instance (Port_general g) -> g.gen_kind = Async_input
      | Ast.Intf_spec_port_instance (Port_special s) -> (
          match s.special_input_kind with Some Async -> true | _ -> false)
      | Ast.Intf_spec_import qi -> (
          let name = Ast.qual_ident_to_string qi.data in
          if SSet.mem name visited then false
          else
            let visited' = SSet.add name visited in
            match SMap.find_opt name tu_env.interfaces with
            | Some sub -> interface_has_async_input_deep tu_env visited' sub
            | None -> false))
    intf.intf_members

(* ── Port requirement checks ──────────────────────────────────────── *)

let check_command_port_reqs ~scope (comp : Ast.def_component) =
  if not (has_commands comp) then []
  else
    let missing kind port_name =
      if not (has_special_port kind comp) then
        [
          error ~sm_name:scope comp.comp_name.loc
            (Fmt.str "component '%s' has commands but no %s port"
               comp.comp_name.data port_name);
        ]
      else []
    in
    missing Command_recv "command recv"
    @ missing Command_reg "command reg"
    @ missing Command_resp "command resp"

let check_param_port_reqs ~scope (comp : Ast.def_component) =
  if not (has_params comp) then []
  else
    let missing kind port_name =
      if not (has_special_port kind comp) then
        [
          error ~sm_name:scope comp.comp_name.loc
            (Fmt.str "component '%s' has parameters but no %s port"
               comp.comp_name.data port_name);
        ]
      else []
    in
    missing Param_get "param get" @ missing Param_set "param set"

let check_event_port_reqs ~scope (comp : Ast.def_component) =
  if has_events comp && not (has_special_port Event comp) then
    [
      error ~sm_name:scope comp.comp_name.loc
        (Fmt.str "component '%s' has events but no event port"
           comp.comp_name.data);
    ]
  else []

let check_telemetry_port_reqs ~scope (comp : Ast.def_component) =
  if has_telemetry comp && not (has_special_port Telemetry comp) then
    [
      error ~sm_name:scope comp.comp_name.loc
        (Fmt.str "component '%s' has telemetry but no telemetry port"
           comp.comp_name.data);
    ]
  else []

let check_container_port_reqs ~scope (comp : Ast.def_component) =
  let missing kind port_name =
    if has_containers comp && not (has_special_port kind comp) then
      [
        error ~sm_name:scope comp.comp_name.loc
          (Fmt.str "component '%s' has containers but no %s port"
             comp.comp_name.data port_name);
      ]
    else []
  in
  missing Product_recv "product recv"
  @ missing Product_request "product request"
  @ missing Product_send "product send"

let check_record_port_reqs ~scope (comp : Ast.def_component) =
  if has_records comp && not (has_containers comp) then
    [
      error ~sm_name:scope comp.comp_name.loc
        (Fmt.str "component '%s' has records but no containers"
           comp.comp_name.data);
    ]
  else []

let check_product_recv_port_reqs ~scope:_ (_comp : Ast.def_component) = []

let check_port_requirements ~scope tu_env (comp : Ast.def_component) =
  let async_diags =
    match comp.comp_kind with
    | Active | Queued ->
        if not (has_async_input tu_env comp) then
          [
            error ~sm_name:scope comp.comp_name.loc
              (Fmt.str "%s component '%s' must have at least one async input"
                 (match comp.comp_kind with
                 | Active -> "active"
                 | Queued -> "queued"
                 | Passive -> "passive")
                 comp.comp_name.data);
          ]
        else []
    | Passive -> []
  in
  async_diags
  @ check_command_port_reqs ~scope comp
  @ check_event_port_reqs ~scope comp
  @ check_param_port_reqs ~scope comp
  @ check_telemetry_port_reqs ~scope comp
  @ check_container_port_reqs ~scope comp
  @ check_record_port_reqs ~scope comp
  @ check_product_recv_port_reqs ~scope comp

(* ── Per-member spec checks ───────────────────────────────────────── *)

let check_command_spec ~scope tu_env (comp : Ast.def_component)
    (cmd : Ast.spec_command) =
  let diags = ref [] in
  let add_all ds = diags := List.rev_append ds !diags in
  if cmd.cmd_kind = Command_async && comp.comp_kind = Passive then
    add_all
      [
        error ~sm_name:scope cmd.cmd_name.loc
          (Fmt.str "async command '%s' not allowed in passive component"
             cmd.cmd_name.data);
      ];
  (match cmd.cmd_opcode with
  | Some e -> add_all (check_nonneg_id ~scope tu_env e "command opcode")
  | None -> ());
  (match cmd.cmd_priority with
  | Some e -> add_all (check_numeric_expr ~scope tu_env e "command priority")
  | None -> ());
  (if cmd.cmd_kind <> Command_async then
     match cmd.cmd_priority with
     | Some e ->
         add_all
           [
             error ~sm_name:scope e.loc
               "priority not allowed on sync/guarded command";
           ]
     | None -> ());
  (if cmd.cmd_kind <> Command_async then
     match cmd.cmd_queue_full with
     | Some qf ->
         add_all
           [
             error ~sm_name:scope qf.loc
               "queue full not allowed on sync/guarded command";
           ]
     | None -> ());
  add_all (check_command_params ~scope cmd);
  List.rev !diags

let check_event_spec ~scope tu_env (ev : Ast.spec_event) =
  let diags = ref [] in
  let add_all ds = diags := List.rev_append ds !diags in
  (match ev.event_id with
  | Some e -> add_all (check_nonneg_id ~scope tu_env e "event ID")
  | None -> ());
  let n_params = List.length ev.event_params in
  let n_repls = count_format_repls ev.event_format.data in
  if n_repls <> n_params then
    add_all
      [
        error ~sm_name:scope ev.event_format.loc
          (Fmt.str
             "event '%s' format string has %d replacement%s but %d parameter%s"
             ev.event_name.data n_repls
             (if n_repls <> 1 then "s" else "")
             n_params
             (if n_params <> 1 then "s" else ""));
      ];
  (match ev.event_throttle with
  | Some t -> (
      add_all
        (check_numeric_expr ~scope tu_env t.throttle_count "throttle count");
      (match t.throttle_every with
      | Some e ->
          add_all (check_numeric_expr ~scope tu_env e "throttle interval")
      | None -> ());
      let v, _ = eval_expr ~scope tu_env t.throttle_count in
      match v with
      | Val_int n when n < 0 ->
          add_all
            [
              error ~sm_name:scope t.throttle_count.loc
                "throttle count must be non-negative";
            ]
      | Val_int 0 ->
          add_all
            [
              error ~sm_name:scope t.throttle_count.loc
                "throttle count must be positive";
            ]
      | _ -> ())
  | None -> ());
  List.rev !diags

let check_general_port_spec ~scope tu_env (comp : Ast.def_component)
    (g : Ast.port_instance_general) =
  let diags = ref [] in
  let add_all ds = diags := List.rev_append ds !diags in
  if g.gen_kind = Async_input && comp.comp_kind = Passive then
    add_all
      [
        error ~sm_name:scope g.gen_name.loc
          (Fmt.str "async input port '%s' not allowed in passive component"
             g.gen_name.data);
      ];
  (match g.gen_priority with
  | Some e -> add_all (check_numeric_expr ~scope tu_env e "port priority")
  | None -> ());
  (if g.gen_kind <> Async_input then
     match g.gen_priority with
     | Some e ->
         add_all
           [
             error ~sm_name:scope e.loc "priority not allowed on non-async port";
           ]
     | None -> ());
  (if g.gen_kind <> Async_input then
     match g.gen_queue_full with
     | Some qf ->
         add_all
           [
             error ~sm_name:scope qf.loc
               "queue full not allowed on non-async port";
           ]
     | None -> ());
  (match g.gen_size with
  | Some e -> add_all (check_numeric_expr ~scope tu_env e "port array size")
  | None -> ());
  (match g.gen_port with
  | Some qi ->
      add_all (check_symbol_as_port ~scope tu_env qi);
      if g.gen_kind = Async_input then
        add_all (check_async_port_type ~scope tu_env qi g.gen_name.data)
  | None -> ());
  List.rev !diags

(* ── Component type definition checks ─────────────────────────────── *)

let is_undef_in_comp ~scope tu_env comp_types name
    (qi : Ast.qual_ident Ast.node) =
  if
    (not (Hashtbl.mem comp_types name))
    && (not (Check_core.is_builtin_type name))
    && Option.is_none (resolve_symbol tu_env qi.data)
  then [ error ~sm_name:scope qi.loc (Fmt.str "undefined type '%s'" name) ]
  else []

let qual_ident_name (qi : Ast.qual_ident) =
  match qi with
  | Ast.Unqualified id -> id.data
  | _ -> Ast.qual_ident_to_string qi

let check_undef_refs ~scope tu_env comp_types comp_constants
    (e : Ast.expr Ast.node) =
  let ids = Check_core.expr_ident_refs e in
  List.concat_map
    (fun (id : Ast.ident Ast.node) ->
      if
        (not (Hashtbl.mem comp_constants id.data))
        && (not (Hashtbl.mem comp_types id.data))
        && Option.is_none (SMap.find_opt id.data tu_env.constants)
        && Option.is_none (resolve_symbol tu_env (Ast.Unqualified id))
      then
        [
          error ~sm_name:scope id.loc (Fmt.str "undefined symbol '%s'" id.data);
        ]
      else [])
    ids

let check_array_def ~scope tu_env comp_types comp_constants (a : Ast.def_array)
    =
  let diags = ref [] in
  let add_all ds = diags := List.rev_append ds !diags in
  (match a.array_elt_type.data with
  | Ast.Type_qual qi ->
      add_all
        (is_undef_in_comp ~scope tu_env comp_types (qual_ident_name qi.data) qi)
  | _ -> ());
  (match a.array_format with
  | Some fmt ->
      if not (is_numeric_type a.array_elt_type.data) then
        let is_alias_numeric =
          match a.array_elt_type.data with
          | Ast.Type_qual qi -> (
              let name = qual_ident_name qi.data in
              match Hashtbl.mem comp_types name with
              | true -> false
              | false -> false)
          | _ -> false
        in
        if not is_alias_numeric then
          add_all
            [
              error ~sm_name:scope fmt.loc
                (Fmt.str "format specifier on non-numeric array '%s'"
                   a.array_name.data);
            ]
  | None -> ());
  (match a.array_default with
  | Some e ->
      add_all (check_expr ~scope tu_env e);
      let v, _ = eval_expr ~scope tu_env e in
      (match v with
      | Val_string _ ->
          add_all
            [
              error ~sm_name:scope e.loc
                (Fmt.str
                   "array '%s' default must be an array expression, got string"
                   a.array_name.data);
            ]
      | _ -> ());
      add_all (check_undef_refs ~scope tu_env comp_types comp_constants e)
  | None -> ());
  List.rev !diags

let check_enum_def ~scope tu_env comp_types comp_constants (e : Ast.def_enum) =
  let diags = ref [] in
  let add_all ds = diags := List.rev_append ds !diags in
  (match e.enum_type with
  | Some t -> (
      match t.data with
      | Ast.Type_qual qi ->
          add_all
            (is_undef_in_comp ~scope tu_env comp_types (qual_ident_name qi.data)
               qi)
      | _ -> ())
  | None -> ());
  List.iter
    (fun ann ->
      let c : Ast.def_enum_constant = (Ast.unannotate ann).Ast.data in
      match c.enum_const_value with
      | Some expr ->
          let ids = Check_core.expr_ident_refs expr in
          List.iter
            (fun (id : Ast.ident Ast.node) ->
              if
                (not (Hashtbl.mem comp_constants id.data))
                && (not (Hashtbl.mem comp_types id.data))
                && not
                     (SMap.mem id.data
                        (match resolve_symbol tu_env (Ast.Unqualified id) with
                        | Some (Sk_constant, _) -> SMap.singleton id.data ()
                        | _ -> SMap.empty))
              then
                add_all
                  [
                    error ~sm_name:scope id.loc
                      (Fmt.str "undefined constant '%s'" id.data);
                  ])
            ids
      | None -> ())
    e.enum_constants;
  (match e.enum_default with
  | Some d -> (
      add_all (check_expr ~scope tu_env d);
      let v, _ = eval_expr ~scope tu_env d in
      match v with
      | Val_string _ ->
          add_all
            [
              error ~sm_name:scope d.loc
                "enum default must be a numeric expression";
            ]
      | _ -> ())
  | None -> ());
  List.rev !diags

let check_struct_def ~scope tu_env comp_types comp_constants
    (s : Ast.def_struct) =
  let diags = ref [] in
  let add_all ds = diags := List.rev_append ds !diags in
  List.iter
    (fun ann ->
      let m : Ast.struct_type_member = (Ast.unannotate ann).Ast.data in
      match m.struct_mem_type.data with
      | Ast.Type_qual qi ->
          add_all
            (is_undef_in_comp ~scope tu_env comp_types (qual_ident_name qi.data)
               qi)
      | _ -> ())
    s.struct_members;
  List.iter
    (fun ann ->
      let m : Ast.struct_type_member = (Ast.unannotate ann).Ast.data in
      match m.struct_mem_format with
      | Some fmt ->
          if not (is_numeric_type m.struct_mem_type.data) then
            add_all
              [
                error ~sm_name:scope fmt.loc
                  (Fmt.str "format specifier on non-numeric member '%s'"
                     m.struct_mem_name.data);
              ]
      | None -> ())
    s.struct_members;
  (match s.struct_default with
  | Some e ->
      add_all (check_expr ~scope tu_env e);
      (match e.data with
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
          List.iter
            (fun (m : Ast.struct_member Ast.node) ->
              if not (List.mem m.data.sm_name.data known) then
                add_all
                  [
                    error ~sm_name:scope m.data.sm_name.loc
                      (Fmt.str "unknown member '%s' in struct '%s' default"
                         m.data.sm_name.data s.struct_name.data);
                  ])
            ms
      | _ -> ());
      add_all (check_undef_refs ~scope tu_env comp_types comp_constants e)
  | None -> ());
  List.rev !diags

(* ── Special port and constant helpers ────────────────────────────── *)

let string_of_special_port_kind = function
  | Ast.Command_recv -> "command recv"
  | Command_reg -> "command reg"
  | Command_resp -> "command resp"
  | Event -> "event"
  | Param_get -> "param get"
  | Param_set -> "param set"
  | Product_get -> "product get"
  | Product_recv -> "product recv"
  | Product_request -> "product request"
  | Product_send -> "product send"
  | Telemetry -> "telemetry"
  | Text_event -> "text event"
  | Time_get -> "time get"

let fw_port_for_special_kind = function
  | Ast.Command_recv -> Some "Fw.Cmd"
  | Command_reg -> Some "Fw.CmdReg"
  | Command_resp -> Some "Fw.CmdResponse"
  | Event -> Some "Fw.Log"
  | Param_get -> Some "Fw.PrmGet"
  | Param_set -> Some "Fw.PrmSet"
  | Product_recv -> Some "Fw.DpResponse"
  | Product_request -> Some "Fw.DpRequest"
  | Product_send -> Some "Fw.DpSend"
  | Telemetry -> Some "Fw.Tlm"
  | Text_event -> Some "Fw.LogText"
  | Time_get -> Some "Fw.Time"
  | Product_get -> None

let resolve_fw_port tu_env fw_name =
  match String.split_on_char '.' fw_name with
  | [ modname; portname ] -> (
      match SMap.find_opt modname tu_env.modules with
      | Some sub -> SMap.mem portname sub.port_defs
      | None -> false)
  | _ -> false

let special_port_allows_input_kind = function
  | Ast.Product_recv | Product_get -> true
  | Command_recv | Command_reg | Command_resp | Event | Param_get | Param_set
  | Product_request | Product_send | Telemetry | Text_event | Time_get ->
      false

let check_non_async_special ~scope (s : Ast.port_instance_special) =
  (match s.special_priority with
    | Some e ->
        [
          error ~sm_name:scope e.loc
            "priority not allowed on non-async special port";
        ]
    | None -> [])
  @
  match s.special_queue_full with
  | Some qf ->
      [
        error ~sm_name:scope qf.loc
          "queue full not allowed on non-async special port";
      ]
  | None -> []

let check_special_port_spec ~scope tu_env (comp : Ast.def_component)
    (s : Ast.port_instance_special) =
  let is_async =
    match s.special_input_kind with Some Async -> true | _ -> false
  in
  (if not is_async then check_non_async_special ~scope s else [])
  @ (match s.special_priority with
    | Some e -> check_numeric_expr ~scope tu_env e "special port priority"
    | None -> [])
  @ (if is_async && comp.comp_kind = Passive then
       [
         error ~sm_name:scope s.special_name.loc
           (Fmt.str "async special port '%s' not allowed in passive component"
              s.special_name.data);
       ]
     else [])
  @ (if
       Option.is_some s.special_input_kind
       && not (special_port_allows_input_kind s.special_kind)
     then
       [
         error ~sm_name:scope s.special_name.loc
           (Fmt.str "input kind not allowed on %s port"
              (string_of_special_port_kind s.special_kind));
       ]
     else [])
  @ (if
       Option.is_none s.special_input_kind
       && special_port_allows_input_kind s.special_kind
     then
       [
         error ~sm_name:scope s.special_name.loc
           (Fmt.str "%s port requires an input kind (sync, async, or guarded)"
              (string_of_special_port_kind s.special_kind));
       ]
     else [])
  @
  match fw_port_for_special_kind s.special_kind with
  | Some fw_name ->
      if not (resolve_fw_port tu_env fw_name) then
        [
          error ~sm_name:scope s.special_name.loc
            (Fmt.str "undefined port %s (required for %s port)" fw_name
               (string_of_special_port_kind s.special_kind));
        ]
      else []
  | None -> []

let check_constant_def ~scope tu_env comp_types comp_constants
    (c : Ast.def_constant) =
  let ids = Check_core.expr_ident_refs c.const_value in
  List.concat_map
    (fun (id : Ast.ident Ast.node) ->
      if
        (not (Hashtbl.mem comp_constants id.data))
        && (not (Hashtbl.mem comp_types id.data))
        && Option.is_none (SMap.find_opt id.data tu_env.constants)
      then
        [
          error ~sm_name:scope id.loc
            (Fmt.str "undefined constant '%s'" id.data);
        ]
      else [])
    ids

(* ── Per-member dispatch ──────────────────────────────────────────── *)

let check_member ~scope tu_env (comp : Ast.def_component) comp_types
    comp_constants (member : Ast.component_member) =
  match member with
  | Ast.Comp_spec_command cmd -> check_command_spec ~scope tu_env comp cmd
  | Ast.Comp_spec_event ev -> check_event_spec ~scope tu_env ev
  | Ast.Comp_spec_param p -> (
      (match p.param_id with
        | Some e -> check_nonneg_id ~scope tu_env e "parameter ID"
        | None -> [])
      @ (match p.param_set_opcode with
        | Some e -> check_nonneg_id ~scope tu_env e "parameter set opcode"
        | None -> [])
      @
      match p.param_save_opcode with
      | Some e -> check_nonneg_id ~scope tu_env e "parameter save opcode"
      | None -> [])
  | Ast.Comp_spec_tlm_channel t ->
      (match t.tlm_id with
        | Some e -> check_nonneg_id ~scope tu_env e "telemetry channel ID"
        | None -> [])
      @ List.concat_map
          (fun (_, e) -> check_numeric_expr ~scope tu_env e "telemetry limit")
          (t.tlm_low @ t.tlm_high)
  | Ast.Comp_spec_port_instance (Port_general g) ->
      check_general_port_spec ~scope tu_env comp g
  | Ast.Comp_spec_port_instance (Port_special s) ->
      check_special_port_spec ~scope tu_env comp s
  | Ast.Comp_spec_internal_port ip ->
      (match ip.internal_priority with
        | Some e -> check_numeric_expr ~scope tu_env e "internal port priority"
        | None -> [])
      @ check_internal_port_params ~scope ip
      @
      if comp.comp_kind = Passive then
        [
          error ~sm_name:scope ip.internal_name.loc
            (Fmt.str "internal port '%s' not allowed in passive component"
               ip.internal_name.data);
        ]
      else []
  | Ast.Comp_spec_container c -> (
      (match c.container_id with
        | Some e -> check_nonneg_id ~scope tu_env e "container ID"
        | None -> [])
      @
      match c.container_default_priority with
      | Some e -> check_numeric_expr ~scope tu_env e "container priority"
      | None -> [])
  | Ast.Comp_spec_record r -> (
      match r.record_id with
      | Some e -> check_nonneg_id ~scope tu_env e "record ID"
      | None -> [])
  | Ast.Comp_spec_sm_instance smi ->
      let sm_name = Ast.qual_ident_to_string smi.smi_machine.data in
      let is_comp_local =
        List.exists
          (fun ann ->
            match (Ast.unannotate ann).Ast.data with
            | Ast.Comp_def_state_machine sm -> sm.sm_name.data = sm_name
            | _ -> false)
          comp.comp_members
      in
      (if is_comp_local then []
       else check_symbol_as_state_machine ~scope tu_env smi.smi_machine)
      @ (match smi.smi_priority with
        | Some e ->
            check_numeric_expr ~scope tu_env e "state machine instance priority"
        | None -> [])
      @
      if comp.comp_kind = Passive then
        [
          error ~sm_name:scope smi.smi_name.loc
            (Fmt.str
               "state machine instance '%s' not allowed in passive component"
               smi.smi_name.data);
        ]
      else []
  | Ast.Comp_def_array a ->
      check_array_def ~scope tu_env comp_types comp_constants a
  | Ast.Comp_def_enum e ->
      check_enum_def ~scope tu_env comp_types comp_constants e
  | Ast.Comp_def_struct s ->
      check_struct_def ~scope tu_env comp_types comp_constants s
  | Ast.Comp_def_constant c ->
      check_constant_def ~scope tu_env comp_types comp_constants c
  | _ -> []

(* ── Duplicate numbered ID detection ──────────────────────────────── *)

let check_duplicate_numbered_ids ~scope tu_env ~kind members
    ~(extract :
       Ast.component_member -> (Ast.loc * Ast.expr Ast.node option) option) =
  let tbl = Hashtbl.create 8 in
  let idx = ref 0 in
  let diags = ref [] in
  List.iter
    (fun ann ->
      match extract (Ast.unannotate ann).Ast.data with
      | Some (name_loc, id_opt) ->
          let id =
            match id_opt with
            | Some e -> (
                let v, _ = eval_expr ~scope tu_env e in
                match v with Val_int n -> n | _ -> -1 - !idx)
            | None -> -1 - !idx
          in
          (match Hashtbl.find_opt tbl id with
          | Some prev_loc when id >= 0 ->
              diags :=
                error ~sm_name:scope name_loc
                  (Fmt.str "duplicate %s 0x%X (first at %s:%d:%d)" kind id
                     prev_loc.Ast.file prev_loc.line prev_loc.col)
                :: !diags
          | _ -> Hashtbl.replace tbl id name_loc);
          incr idx
      | None -> ())
    members;
  List.rev !diags

let check_all_duplicate_ids ~scope tu_env members =
  check_duplicate_numbered_ids ~scope tu_env ~kind:"command opcode" members
    ~extract:(function
    | Ast.Comp_spec_command cmd -> Some (cmd.cmd_name.loc, cmd.cmd_opcode)
    | _ -> None)
  @ check_duplicate_numbered_ids ~scope tu_env ~kind:"event ID" members
      ~extract:(function
      | Ast.Comp_spec_event ev -> Some (ev.event_name.loc, ev.event_id)
      | _ -> None)
  @ check_duplicate_numbered_ids ~scope tu_env ~kind:"parameter ID" members
      ~extract:(function
      | Ast.Comp_spec_param p -> Some (p.param_name.loc, p.param_id)
      | _ -> None)
  @ check_duplicate_numbered_ids ~scope tu_env ~kind:"telemetry channel ID"
      members ~extract:(function
      | Ast.Comp_spec_tlm_channel t -> Some (t.tlm_name.loc, t.tlm_id)
      | _ -> None)
  @ check_duplicate_numbered_ids ~scope tu_env ~kind:"container ID" members
      ~extract:(function
      | Ast.Comp_spec_container c -> Some (c.container_name.loc, c.container_id)
      | _ -> None)
  @ check_duplicate_numbered_ids ~scope tu_env ~kind:"record ID" members
      ~extract:(function
      | Ast.Comp_spec_record r -> Some (r.record_name.loc, r.record_id)
      | _ -> None)

(* ── Duplicate special ports ──────────────────────────────────────── *)

let check_duplicate_special_ports ~scope members =
  let seen = Hashtbl.create 8 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_special s) ->
          let kind_str = string_of_special_port_kind s.special_kind in
          let diags =
            match Hashtbl.find_opt seen kind_str with
            | Some prev_loc ->
                [
                  error ~sm_name:scope s.special_name.loc
                    (Fmt.str "duplicate %s port (first at %s:%d:%d)" kind_str
                       prev_loc.Ast.file prev_loc.line prev_loc.col);
                ]
            | None -> []
          in
          Hashtbl.replace seen kind_str s.special_name.loc;
          diags
      | _ -> [])
    members

(* ── Import constraint checks ─────────────────────────────────────── *)

let check_passive_async_imports ~scope tu_env (comp : Ast.def_component) =
  if comp.comp_kind <> Passive then []
  else
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Comp_spec_import_interface qi -> (
            let name = Ast.qual_ident_to_string qi.data in
            match SMap.find_opt name tu_env.interfaces with
            | Some intf ->
                if interface_has_async_input_deep tu_env SSet.empty intf then
                  [
                    error ~sm_name:scope qi.loc
                      (Fmt.str
                         "passive component '%s' imports interface '%s' which \
                          has async input ports"
                         comp.comp_name.data name);
                  ]
                else []
            | None -> [])
        | _ -> [])
      comp.comp_members

let check_import_port_conflicts ~scope tu_env (comp : Ast.def_component) =
  let comp_ports = Hashtbl.create 8 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_general g) ->
          Hashtbl.replace comp_ports g.gen_name.data g.gen_name.loc
      | Ast.Comp_spec_port_instance (Port_special s) ->
          Hashtbl.replace comp_ports s.special_name.data s.special_name.loc
      | _ -> ())
    comp.comp_members;
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_import_interface qi -> (
          let name = Ast.qual_ident_to_string qi.data in
          match SMap.find_opt name tu_env.interfaces with
          | Some intf ->
              List.concat_map
                (fun iann ->
                  match (Ast.unannotate iann).Ast.data with
                  | Ast.Intf_spec_port_instance (Port_general g) -> (
                      let pname = g.gen_name.data in
                      match Hashtbl.find_opt comp_ports pname with
                      | Some prev_loc ->
                          [
                            error ~sm_name:scope qi.loc
                              (Fmt.str
                                 "import '%s' introduces port '%s' which \
                                  conflicts with existing port at %s:%d:%d"
                                 name pname prev_loc.Ast.file prev_loc.line
                                 prev_loc.col);
                          ]
                      | None -> [])
                  | _ -> [])
                intf.intf_members
          | None -> [])
      | _ -> [])
    comp.comp_members

let check_duplicate_interface_imports ~scope (comp : Ast.def_component) =
  let seen = Hashtbl.create 4 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_import_interface qi ->
          let name = Ast.qual_ident_to_string qi.data in
          let diags =
            match Hashtbl.find_opt seen name with
            | Some prev_loc ->
                [
                  error ~sm_name:scope qi.loc
                    (Fmt.str
                       "duplicate interface import '%s' (first at %s:%d:%d)"
                       name prev_loc.Ast.file prev_loc.line prev_loc.col);
                ]
            | None -> []
          in
          Hashtbl.replace seen name qi.loc;
          diags
      | _ -> [])
    comp.comp_members

let check_import_constraints ~scope tu_env (comp : Ast.def_component) =
  check_passive_async_imports ~scope tu_env comp
  @ check_import_port_conflicts ~scope tu_env comp
  @ check_duplicate_interface_imports ~scope comp

(* ── Port matching checks ─────────────────────────────────────────── *)

let check_single_port_match ~scope port_names port_sizes
    (pm : Ast.spec_port_matching) =
  let p1 = pm.match_port1 in
  let p2 = pm.match_port2 in
  let same =
    if p1.data = p2.data then
      [
        error ~sm_name:scope p2.loc
          (Fmt.str "port matching: '%s' matched with itself" p1.data);
      ]
    else []
  in
  let undef1 =
    if not (Hashtbl.mem port_names p1.data) then
      [
        error ~sm_name:scope p1.loc
          (Fmt.str "port matching: '%s' is not a port instance" p1.data);
      ]
    else []
  in
  let undef2 =
    if not (Hashtbl.mem port_names p2.data) then
      [
        error ~sm_name:scope p2.loc
          (Fmt.str "port matching: '%s' is not a port instance" p2.data);
      ]
    else []
  in
  let size_mismatch =
    if Hashtbl.mem port_names p1.data && Hashtbl.mem port_names p2.data then
      match
        ( Hashtbl.find_opt port_sizes p1.data,
          Hashtbl.find_opt port_sizes p2.data )
      with
      | Some (Some s1), Some (Some s2) when s1 <> s2 ->
          [
            error ~sm_name:scope p2.loc
              (Fmt.str "port matching: '%s' has size %d but '%s' has size %d"
                 p1.data s1 p2.data s2);
          ]
      | _ -> []
    else []
  in
  same @ undef1 @ undef2 @ size_mismatch

let check_port_matching ~scope tu_env (comp : Ast.def_component) =
  let port_names = Hashtbl.create 8 in
  let port_sizes = Hashtbl.create 8 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_general g) ->
          Hashtbl.replace port_names g.gen_name.data g.gen_name.loc;
          let size =
            match g.gen_size with
            | Some e -> (
                let v, _ = eval_expr ~scope tu_env e in
                match v with Val_int n -> Some n | _ -> None)
            | None -> None
          in
          Hashtbl.replace port_sizes g.gen_name.data size
      | _ -> ())
    comp.comp_members;
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_matching pm ->
          check_single_port_match ~scope port_names port_sizes pm
      | _ -> [])
    comp.comp_members

(* ── Displayability checks for component members ─────────────────── *)

let is_displayable_in_comp ~tu_members (comp : Ast.def_component)
    (tn : Ast.type_name) =
  match tn with
  | Ast.Type_bool | Ast.Type_int _ | Ast.Type_float _ | Ast.Type_string _ ->
      true
  | Ast.Type_qual qi ->
      let name = Ast.qual_ident_to_string qi.data in
      let is_comp_abstract =
        List.exists
          (fun ann ->
            match (Ast.unannotate ann).Ast.data with
            | Ast.Comp_def_abs_type t -> t.abs_name.data = name
            | _ -> false)
          comp.comp_members
      in
      if is_comp_abstract then false
      else Check_def.is_type_displayable tu_members tn

let check_displayable_members ~scope ~tu_members (comp : Ast.def_component) =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_command cmd ->
          List.concat_map
            (fun ann ->
              let fp : Ast.formal_param = (Ast.unannotate ann).Ast.data in
              if not (is_displayable_in_comp ~tu_members comp fp.fp_type.data)
              then
                [
                  error ~sm_name:scope fp.fp_name.loc
                    (Fmt.str "command parameter '%s' type is not displayable"
                       fp.fp_name.data);
                ]
              else [])
            cmd.cmd_params
      | Ast.Comp_spec_record r ->
          if not (is_displayable_in_comp ~tu_members comp r.record_type.data)
          then
            [
              error ~sm_name:scope r.record_name.loc
                (Fmt.str "product record '%s' type is not displayable"
                   r.record_name.data);
            ]
          else []
      | Ast.Comp_spec_tlm_channel t ->
          if not (is_displayable_in_comp ~tu_members comp t.tlm_type.data) then
            [
              error ~sm_name:scope t.tlm_name.loc
                (Fmt.str "telemetry channel '%s' type is not displayable"
                   t.tlm_name.data);
            ]
          else []
      | _ -> [])
    comp.comp_members

(* ── Component definition check ───────────────────────────────────── *)

let check_component ~scope ~tu_members tu_env (comp : Ast.def_component) =
  let comp_types, comp_constants = build_comp_types comp in
  check_port_requirements ~scope tu_env comp
  @ List.concat_map
      (fun ann ->
        check_member ~scope tu_env comp comp_types comp_constants
          (Ast.unannotate ann).Ast.data)
      comp.comp_members
  @ check_all_duplicate_ids ~scope tu_env comp.comp_members
  @ check_duplicate_special_ports ~scope comp.comp_members
  @ check_import_constraints ~scope tu_env comp
  @ check_port_matching ~scope tu_env comp
  @ check_displayable_members ~scope ~tu_members comp

(* ── Port definition checks ───────────────────────────────────────── *)

let check_port_def ~scope tu_env (p : Ast.def_port) =
  let diags = ref [] in
  let add_all ds = diags := List.rev_append ds !diags in
  List.iter
    (fun ann ->
      let fp : Ast.formal_param = (Ast.unannotate ann).Ast.data in
      add_all (check_type_name ~scope tu_env fp.fp_type))
    p.port_params;
  (match p.port_return with
  | Some t -> add_all (check_type_name ~scope tu_env t)
  | None -> ());
  let seen = Hashtbl.create 8 in
  List.iter
    (fun ann ->
      let fp : Ast.formal_param = (Ast.unannotate ann).Ast.data in
      let name = fp.fp_name.data in
      match Hashtbl.find_opt seen name with
      | Some prev_loc ->
          add_all
            [
              error ~sm_name:scope fp.fp_name.loc
                (Fmt.str "duplicate parameter '%s' (first at %s:%d:%d)" name
                   prev_loc.Ast.file prev_loc.line prev_loc.col);
            ]
      | None -> Hashtbl.replace seen name fp.fp_name.loc)
    p.port_params;
  List.rev !diags

(* ── Interface checks ──────────────────────────────────────────────── *)

let check_intf_duplicate_ports ~scope (intf : Ast.def_interface) =
  let seen = Hashtbl.create 8 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Intf_spec_port_instance (Port_general g) ->
          let name = g.gen_name.data in
          let diags =
            match Hashtbl.find_opt seen name with
            | Some prev_loc ->
                [
                  error ~sm_name:scope g.gen_name.loc
                    (Fmt.str "duplicate port '%s' (first at %s:%d:%d)" name
                       prev_loc.Ast.file prev_loc.line prev_loc.col);
                ]
            | None -> []
          in
          Hashtbl.replace seen name g.gen_name.loc;
          diags
      | Ast.Intf_spec_port_instance (Port_special s) ->
          let name = s.special_name.data in
          let diags =
            match Hashtbl.find_opt seen name with
            | Some prev_loc ->
                [
                  error ~sm_name:scope s.special_name.loc
                    (Fmt.str "duplicate port '%s' (first at %s:%d:%d)" name
                       prev_loc.Ast.file prev_loc.line prev_loc.col);
                ]
            | None -> []
          in
          Hashtbl.replace seen name s.special_name.loc;
          diags
      | _ -> [])
    intf.intf_members

let check_interface ~scope tu_env (intf : Ast.def_interface) =
  check_intf_duplicate_ports ~scope intf
  @ List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Intf_spec_port_instance (Port_general g) -> (
            match g.gen_port with
            | Some qi -> check_symbol_as_port ~scope tu_env qi
            | None -> [])
        | _ -> [])
      intf.intf_members
  @ (let seen = Hashtbl.create 4 in
     List.concat_map
       (fun ann ->
         match (Ast.unannotate ann).Ast.data with
         | Ast.Intf_spec_import qi ->
             let name = Ast.qual_ident_to_string qi.data in
             let diags =
               match Hashtbl.find_opt seen name with
               | Some prev_loc ->
                   [
                     error ~sm_name:scope qi.loc
                       (Fmt.str
                          "duplicate interface import '%s' (first at %s:%d:%d)"
                          name prev_loc.Ast.file prev_loc.line prev_loc.col);
                   ]
               | None -> []
             in
             Hashtbl.replace seen name qi.loc;
             diags
         | _ -> [])
       intf.intf_members)
  @ List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Intf_spec_import qi ->
            let name = Ast.qual_ident_to_string qi.data in
            if name = intf.intf_name.data then
              [
                error ~sm_name:scope qi.loc
                  (Fmt.str "interface '%s' imports itself" name);
              ]
            else []
        | _ -> [])
      intf.intf_members

(* ── Entry point ───────────────────────────────────────────────────── *)

let run ~scope tu_env members =
  let rec walk ~scope env members =
    List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Mod_def_component c ->
            let s = scope ^ "." ^ c.comp_name.data in
            check_component ~scope:s ~tu_members:members env c
        | Ast.Mod_def_module m ->
            let s = scope ^ "." ^ m.module_name.data in
            let sub =
              match SMap.find_opt m.module_name.data env.modules with
              | Some e -> overlay_env ~parent:env ~child:e
              | None -> env
            in
            walk ~scope:s sub m.module_members
        | Ast.Mod_def_port p -> check_port_def ~scope env p
        | Ast.Mod_def_interface i -> check_interface ~scope env i
        | _ -> [])
      members
  in
  walk ~scope tu_env members

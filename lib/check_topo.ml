(** Component instance and topology validation.

    Validates component instances (property requirements by component kind),
    instance ID conflicts, and topology members (imports, connection patterns,
    instance references). This module is internal to the [fpp] library. *)

open Check_env
open Check_tu_env

(* ── Component instance property helpers ──────────────────────────── *)

let check_inst_requires ~scope (i : Ast.def_component_instance) kind_str field
    field_name =
  if Option.is_none field then
    [
      error ~sm_name:scope i.inst_name.loc
        (Fmt.str "%s component instance '%s' requires %s" kind_str
           i.inst_name.data field_name);
    ]
  else []

let check_inst_forbids ~scope (i : Ast.def_component_instance) kind_str field
    field_name =
  if Option.is_some field then
    [
      error ~sm_name:scope i.inst_name.loc
        (Fmt.str "%s component instance '%s' cannot have %s" kind_str
           i.inst_name.data field_name);
    ]
  else []

let check_kind_props ~scope (i : Ast.def_component_instance)
    (kind : Ast.component_kind) =
  match kind with
  | Active ->
      check_inst_requires ~scope i "active" i.inst_queue_size "queue size"
  | Queued ->
      check_inst_requires ~scope i "queued" i.inst_queue_size "queue size"
      @ check_inst_forbids ~scope i "queued" i.inst_stack_size "stack size"
      @ check_inst_forbids ~scope i "queued" i.inst_priority "priority"
      @ check_inst_forbids ~scope i "queued" i.inst_cpu "cpu"
  | Passive ->
      check_inst_forbids ~scope i "passive" i.inst_queue_size "queue size"
      @ check_inst_forbids ~scope i "passive" i.inst_stack_size "stack size"
      @ check_inst_forbids ~scope i "passive" i.inst_priority "priority"
      @ check_inst_forbids ~scope i "passive" i.inst_cpu "cpu"

let check_base_id ~scope tu_env (i : Ast.def_component_instance) =
  let base_val, base_diags = eval_expr ~scope tu_env i.inst_base_id in
  let range_diags =
    match base_val with
    | Val_int n when n < 0 ->
        [
          error ~sm_name:scope i.inst_base_id.loc
            (Fmt.str "component instance '%s' has negative base ID %d"
               i.inst_name.data n);
        ]
    | Val_int n when n > 0xFFFF_FFFF ->
        [
          error ~sm_name:scope i.inst_base_id.loc
            (Fmt.str
               "component instance '%s' has base ID 0x%X exceeding maximum"
               i.inst_name.data n);
        ]
    | _ -> []
  in
  base_diags @ range_diags

(* ── Init phase helpers ────────────────────────────────────────────── *)

let check_duplicate_init_phases ~scope tu_env init_specs =
  let seen = Hashtbl.create 4 in
  List.concat_map
    (fun ann ->
      let si : Ast.spec_init = (Ast.unannotate ann).Ast.data in
      let v, d = eval_expr ~scope tu_env si.init_phase in
      let dup =
        match v with
        | Val_int n -> (
            match Hashtbl.find_opt seen n with
            | Some prev_loc ->
                [
                  error ~sm_name:scope si.init_phase.loc
                    (Fmt.str "duplicate init phase %d (first at %s:%d:%d)" n
                       prev_loc.Ast.file prev_loc.line prev_loc.col);
                ]
            | None ->
                Hashtbl.replace seen n si.init_phase.loc;
                [])
        | _ -> []
      in
      d @ dup)
    init_specs

let check_init_phase_validity ~scope tu_env init_specs =
  List.concat_map
    (fun ann ->
      let si : Ast.spec_init = (Ast.unannotate ann).Ast.data in
      let nonneg = check_nonneg_id ~scope tu_env si.init_phase "init phase" in
      let undef =
        match si.init_phase.data with
        | Ast.Expr_ident id ->
            if
              Option.is_none (SMap.find_opt id.data tu_env.constants)
              && Option.is_none (resolve_symbol tu_env (Ast.Unqualified id))
            then
              [
                error ~sm_name:scope id.loc
                  (Fmt.str "undefined symbol '%s'" id.data);
              ]
            else []
        | _ -> []
      in
      nonneg @ undef)
    init_specs

(* ── Component instance checks ─────────────────────────────────────── *)

let check_component_instance ~scope tu_env (i : Ast.def_component_instance) =
  let comp_diags =
    match component tu_env i.inst_component with
    | None ->
        [
          error ~sm_name:scope i.inst_component.loc
            (Fmt.str "undefined component '%s'"
               (Ast.qual_ident_to_string i.inst_component.data));
        ]
    | Some comp -> check_kind_props ~scope i comp.comp_kind
  in
  let phase_diags = check_duplicate_init_phases ~scope tu_env i.inst_init in
  let phase_nonneg = check_init_phase_validity ~scope tu_env i.inst_init in
  comp_diags @ check_base_id ~scope tu_env i @ phase_diags @ phase_nonneg

(* ── Instance ID conflict checks ───────────────────────────────────── *)

let instance_id_count tu_env (i : Ast.def_component_instance) =
  match component tu_env i.inst_component with
  | None -> 0
  | Some comp ->
      List.fold_left
        (fun n ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Comp_spec_command _ | Ast.Comp_spec_event _
          | Ast.Comp_spec_tlm_channel _ | Ast.Comp_spec_param _
          | Ast.Comp_spec_container _ | Ast.Comp_spec_record _ ->
              n + 1
          | _ -> n)
        0 comp.comp_members

let check_instance_id_conflicts ~scope tu_env members =
  let instances =
    List.filter_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Mod_def_component_instance i ->
            let base_id =
              let v, _ = eval_expr ~scope tu_env i.inst_base_id in
              match v with Val_int n -> Some n | _ -> None
            in
            let n_ids = instance_id_count tu_env i in
            Some (i, base_id, n_ids)
        | _ -> None)
      members
  in
  let prev = ref [] in
  List.concat_map
    (fun ((i : Ast.def_component_instance), base_opt, n_ids) ->
      let diags =
        match base_opt with
        | Some bi ->
            (* Check if i's base falls in any previous instance's range *)
            let d1 =
              List.filter_map
                (fun ((jj : Ast.def_component_instance), bj, n_j) ->
                  if n_j > 0 && bi >= bj && bi < bj + n_j then
                    Some
                      (errorf ~sm_name:scope i.inst_name.loc
                         "component instance '%s' base ID 0x%X conflicts with \
                          '%s' (at %s:%d:%d)"
                         i.inst_name.data bi jj.inst_name.data
                         jj.inst_name.loc.Ast.file jj.inst_name.loc.line
                         jj.inst_name.loc.col)
                  else None)
                !prev
            in
            (* Check if any previous instance's base falls in i's range *)
            let d2 =
              if n_ids > 0 && d1 = [] then
                List.filter_map
                  (fun ((jj : Ast.def_component_instance), bj, _) ->
                    if bj >= bi && bj < bi + n_ids then
                      Some
                        (errorf ~sm_name:scope i.inst_name.loc
                           "component instance '%s' ID range [0x%X, 0x%X] \
                            conflicts with '%s' (at %s:%d:%d)"
                           i.inst_name.data bi
                           (bi + n_ids - 1)
                           jj.inst_name.data jj.inst_name.loc.Ast.file
                           jj.inst_name.loc.line jj.inst_name.loc.col)
                    else None)
                  !prev
              else []
            in
            d1 @ d2
        | None -> []
      in
      (match base_opt with
      | Some bi -> prev := (i, bi, n_ids) :: !prev
      | None -> ());
      diags)
    instances

(* ── Topology checks ──────────────────────────────────────────────── *)

let check_instance_with_root ~scope tu_env root_env
    (qi : Ast.qual_ident Ast.node) =
  match resolve_symbol tu_env qi.data with
  | Some (Sk_instance, _) -> []
  | Some _ ->
      (* Found in local env but wrong kind *)
      check_symbol_as_instance ~scope tu_env qi
  | None -> (
      (* Fallback to root env *)
      match resolve_symbol root_env qi.data with
      | Some (Sk_instance, _) -> []
      | Some (kind, _) ->
          let a =
            match (string_of_symbol_kind kind).[0] with
            | 'a' | 'e' | 'i' | 'o' | 'u' -> "an"
            | _ -> "a"
          in
          [
            error ~sm_name:scope qi.loc
              (Fmt.str "'%s' is %s %s, not a component instance"
                 (Ast.qual_ident_to_string qi.data)
                 a
                 (string_of_symbol_kind kind));
          ]
      | None ->
          [
            error ~sm_name:scope qi.loc
              (Fmt.str "undefined component instance '%s'"
                 (Ast.qual_ident_to_string qi.data));
          ])

let check_member_refs ~scope ~root_env tu_env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_comp_instance ci ->
          check_instance_with_root ~scope tu_env root_env ci.ci_instance
      | Ast.Topo_spec_top_import qi -> check_symbol_as_topology ~scope tu_env qi
      | _ -> [])
    members

let check_duplicate_topo_instances ~scope members =
  let seen = Hashtbl.create 8 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_comp_instance ci -> (
          let name = Ast.qual_ident_to_string ci.ci_instance.data in
          match Hashtbl.find_opt seen name with
          | Some prev_loc ->
              [
                error ~sm_name:scope ci.ci_instance.loc
                  (Fmt.str
                     "duplicate instance '%s' in topology (first at %s:%d:%d)"
                     name prev_loc.Ast.file prev_loc.line prev_loc.col);
              ]
          | None ->
              Hashtbl.replace seen name ci.ci_instance.loc;
              [])
      | _ -> [])
    members

let string_of_pattern_kind = function
  | Ast.Pattern_command -> "command"
  | Pattern_event -> "event"
  | Pattern_health -> "health"
  | Pattern_param -> "param"
  | Pattern_telemetry -> "telemetry"
  | Pattern_text_event -> "text event"
  | Pattern_time -> "time"

let check_duplicate_patterns ~scope members =
  let seen = Hashtbl.create 8 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_connection_graph (Graph_pattern p) -> (
          let kind_str = string_of_pattern_kind p.pattern_kind in
          match Hashtbl.find_opt seen kind_str with
          | Some prev_loc ->
              [
                error ~sm_name:scope p.pattern_source.loc
                  (Fmt.str "duplicate %s connection pattern (first at %s:%d:%d)"
                     kind_str prev_loc.Ast.file prev_loc.line prev_loc.col);
              ]
          | None ->
              Hashtbl.replace seen kind_str p.pattern_source.loc;
              [])
      | _ -> [])
    members

let check_duplicate_topo_imports ~scope members =
  let seen = Hashtbl.create 8 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_top_import qi -> (
          let name = Ast.qual_ident_to_string qi.data in
          match Hashtbl.find_opt seen name with
          | Some prev_loc ->
              [
                error ~sm_name:scope qi.loc
                  (Fmt.str
                     "duplicate import of topology '%s' (first at %s:%d:%d)"
                     name prev_loc.Ast.file prev_loc.line prev_loc.col);
              ]
          | None ->
              Hashtbl.replace seen name qi.loc;
              [])
      | _ -> [])
    members

(* ── Connection pattern port validation ────────────────────────────── *)

let resolve_instance_comp tu_env name =
  match SMap.find_opt name tu_env.instances with
  | Some i -> component tu_env i.inst_component
  | None -> None

let count_general_ports_of_type (comp : Ast.def_component) port_type_name =
  List.fold_left
    (fun n ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_general g) -> (
          match g.gen_port with
          | Some qi ->
              let tn = Ast.qual_ident_to_string qi.data in
              if tn = port_type_name then n + 1 else n
          | None -> n)
      | _ -> n)
    0 comp.comp_members

let count_input_ports_of_type (comp : Ast.def_component) port_type_name =
  List.fold_left
    (fun n ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_general g)
        when g.gen_kind = Sync_input || g.gen_kind = Async_input
             || g.gen_kind = Guarded_input -> (
          match g.gen_port with
          | Some qi ->
              if Ast.qual_ident_to_string qi.data = port_type_name then n + 1
              else n
          | None -> n)
      | _ -> n)
    0 comp.comp_members

let has_special_port_kind (comp : Ast.def_component) kind =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_special s) -> s.special_kind = kind
      | _ -> false)
    comp.comp_members

let check_source_port ~scope loc comp port_type_name pattern_name =
  let n = count_general_ports_of_type comp port_type_name in
  if n = 0 then
    [
      errorf ~sm_name:scope loc "%s pattern source has no %s port" pattern_name
        port_type_name;
    ]
  else if n > 1 then
    [
      errorf ~sm_name:scope loc
        "%s pattern source has multiple %s ports (expected one)" pattern_name
        port_type_name;
    ]
  else []

let string_of_special_kind = function
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

let check_target_special ~scope loc comp kind pattern_name =
  if not (has_special_port_kind comp kind) then
    [
      errorf ~sm_name:scope loc "%s pattern target has no %s port" pattern_name
        (string_of_special_kind kind);
    ]
  else []

let check_pattern_source ~scope (p : Ast.graph_pattern_kind)
    (source : Ast.qual_ident Ast.node) comp =
  match p with
  | Pattern_command ->
      check_source_port ~scope source.loc comp "Fw.CmdReg" "command"
      @ check_source_port ~scope source.loc comp "Fw.Cmd" "command"
      @ check_source_port ~scope source.loc comp "Fw.CmdResponse" "command"
  | Pattern_event -> check_source_port ~scope source.loc comp "Fw.Log" "event"
  | Pattern_health ->
      let n_in = count_input_ports_of_type comp "Svc.Ping" in
      if n_in = 0 then
        [
          errorf ~sm_name:scope source.loc
            "health pattern source has no Svc.Ping input port";
        ]
      else if n_in > 1 then
        [
          errorf ~sm_name:scope source.loc
            "health pattern source has multiple Svc.Ping input ports";
        ]
      else []
  | Pattern_param ->
      check_source_port ~scope source.loc comp "Fw.PrmGet" "param"
      @ check_source_port ~scope source.loc comp "Fw.PrmSet" "param"
  | Pattern_telemetry ->
      check_source_port ~scope source.loc comp "Fw.Tlm" "telemetry"
  | Pattern_text_event ->
      check_source_port ~scope source.loc comp "Fw.LogText" "text event"
  | Pattern_time -> check_source_port ~scope source.loc comp "Fw.Time" "time"

let check_pattern_target ~scope tu_env (p : Ast.graph_pattern_kind)
    (qi : Ast.qual_ident Ast.node) =
  let tname = Ast.qual_ident_to_string qi.data in
  match resolve_instance_comp tu_env tname with
  | None -> []
  | Some tcomp -> (
      match p with
      | Pattern_command ->
          check_target_special ~scope qi.loc tcomp Ast.Command_recv "command"
          @ check_target_special ~scope qi.loc tcomp Ast.Command_reg "command"
          @ check_target_special ~scope qi.loc tcomp Ast.Command_resp "command"
      | Pattern_event ->
          check_target_special ~scope qi.loc tcomp Ast.Event "event"
      | Pattern_health ->
          let n = count_general_ports_of_type tcomp "Svc.Ping" in
          if n < 2 then
            [
              errorf ~sm_name:scope qi.loc
                "health pattern target needs ping input and output ports";
            ]
          else []
      | Pattern_param ->
          check_target_special ~scope qi.loc tcomp Ast.Param_get "param"
          @ check_target_special ~scope qi.loc tcomp Ast.Param_set "param"
      | Pattern_telemetry ->
          check_target_special ~scope qi.loc tcomp Ast.Telemetry "telemetry"
      | Pattern_text_event ->
          check_target_special ~scope qi.loc tcomp Ast.Text_event "text event"
      | Pattern_time ->
          check_target_special ~scope qi.loc tcomp Ast.Time_get "time")

let check_pattern_ports ~scope tu_env (p : Ast.graph_pattern_kind)
    (source : Ast.qual_ident Ast.node) targets =
  let src_name = Ast.qual_ident_to_string source.data in
  match resolve_instance_comp tu_env src_name with
  | None -> []
  | Some comp ->
      check_pattern_source ~scope p source comp
      @ List.concat_map (check_pattern_target ~scope tu_env p) targets

let check_connection_patterns ~scope tu_env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_connection_graph (Graph_pattern p) ->
          check_pattern_ports ~scope tu_env p.pattern_kind p.pattern_source
            p.pattern_targets
      | _ -> [])
    members

(* ── Direct connection validation ─────────────────────────────────── *)

let component_port (comp : Ast.def_component) port_name =
  List.find_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_instance (Port_general g)
        when g.gen_name.data = port_name ->
          Some g
      | _ -> None)
    comp.comp_members

let resolve_port_type_def tu_env (qi : Ast.qual_ident) =
  let ids = Ast.qual_ident_to_list qi in
  let rec walk env = function
    | [] -> None
    | [ id ] -> SMap.find_opt id.Ast.data env.port_defs
    | id :: rest -> (
        match SMap.find_opt id.Ast.data env.modules with
        | Some sub -> walk sub rest
        | None -> None)
  in
  walk tu_env ids

let port_has_return tu_env (qi : Ast.qual_ident) =
  match resolve_port_type_def tu_env qi with
  | Some def -> Option.is_some def.port_return
  | None -> false

let is_matched_port (comp : Ast.def_component) port_name =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_matching pm ->
          pm.match_port1.data = port_name || pm.match_port2.data = port_name
      | _ -> false)
    comp.comp_members

let check_connection_types ~scope tu_env loc from_port to_port from_inst to_inst
    from_port_name to_port_name =
  let is_serial qi = Ast.qual_ident_to_string qi = "serial" in
  match (from_port.Ast.gen_port, to_port.Ast.gen_port) with
  | Some ft, Some tt ->
      let f_serial = is_serial ft.data in
      let t_serial = is_serial tt.data in
      if f_serial && t_serial then []
      else if f_serial then
        if port_has_return tu_env tt.data then
          [
            errorf ~sm_name:scope loc
              "serial port '%s.%s' cannot connect to typed port '%s.%s' with \
               return type"
              from_inst from_port_name to_inst to_port_name;
          ]
        else []
      else if t_serial then
        if port_has_return tu_env ft.data then
          [
            errorf ~sm_name:scope loc
              "typed port '%s.%s' with return type cannot connect to serial \
               port '%s.%s'"
              from_inst from_port_name to_inst to_port_name;
          ]
        else []
      else
        let ftn = Ast.qual_ident_to_string ft.data in
        let ttn = Ast.qual_ident_to_string tt.data in
        if ftn <> ttn then
          [
            errorf ~sm_name:scope loc
              "port type mismatch: '%s.%s' has type %s but '%s.%s' has type %s"
              from_inst from_port_name ftn to_inst to_port_name ttn;
          ]
        else []
  | Some ft, None ->
      if port_has_return tu_env ft.data then
        [
          errorf ~sm_name:scope loc
            "typed port '%s.%s' with return type cannot connect to serial port \
             '%s.%s'"
            from_inst from_port_name to_inst to_port_name;
        ]
      else []
  | None, Some tt ->
      if port_has_return tu_env tt.data then
        [
          errorf ~sm_name:scope loc
            "serial port '%s.%s' cannot connect to typed port '%s.%s' with \
             return type"
            from_inst from_port_name to_inst to_port_name;
        ]
      else []
  | None, None -> []

let check_direct_connection ~scope tu_env (conn : Ast.connection) =
  let from_pid = conn.conn_from_port.data in
  let to_pid = conn.conn_to_port.data in
  let from_inst = Ast.qual_ident_to_string from_pid.pid_component.data in
  let to_inst = Ast.qual_ident_to_string to_pid.pid_component.data in
  let from_port_name = from_pid.pid_port.data in
  let to_port_name = to_pid.pid_port.data in
  match
    ( resolve_instance_comp tu_env from_inst,
      resolve_instance_comp tu_env to_inst )
  with
  | Some from_comp, Some to_comp -> (
      match
        ( component_port from_comp from_port_name,
          component_port to_comp to_port_name )
      with
      | Some from_port, Some to_port ->
          let type_diags =
            check_connection_types ~scope tu_env conn.conn_from_port.loc
              from_port to_port from_inst to_inst from_port_name to_port_name
          in
          let unmatched_diag =
            if conn.conn_unmatched then
              if not (is_matched_port from_comp from_port_name) then
                [
                  errorf ~sm_name:scope conn.conn_from_port.loc
                    "'unmatched' used on port '%s.%s' which is not in a port \
                     matching"
                    from_inst from_port_name;
                ]
              else []
            else []
          in
          type_diags @ unmatched_diag
      | _ -> [])
  | _ -> []

let check_port_index ~scope tu_env (idx : Ast.expr Ast.node) label =
  let v, diags = eval_expr ~scope tu_env idx in
  let neg =
    match v with
    | Val_int n when n < 0 ->
        [
          errorf ~sm_name:scope idx.loc "negative port number %d in %s" n label;
        ]
    | _ -> []
  in
  diags @ neg

let port_size tu_env (comp : Ast.def_component) port_name =
  match component_port comp port_name with
  | Some g -> (
      match g.gen_size with
      | Some sz -> (
          let v, _ = eval_expr ~scope:"" tu_env sz in
          match v with Val_int n -> Some n | _ -> None)
      | None -> Some 1)
  | None -> None

let check_duplicate_outputs ~scope tu_env connections =
  let seen = Hashtbl.create 16 in
  List.concat_map
    (fun conn_ann ->
      let conn : Ast.connection = (Ast.unannotate conn_ann).Ast.data in
      match conn.conn_from_index with
      | Some ie -> (
          let from_pid = conn.conn_from_port.data in
          let inst = Ast.qual_ident_to_string from_pid.pid_component.data in
          let port = from_pid.pid_port.data in
          let v, _ = eval_expr ~scope tu_env ie in
          match v with
          | Val_int n -> (
              let key = Fmt.str "%s.%s[%d]" inst port n in
              match Hashtbl.find_opt seen key with
              | Some prev_loc ->
                  Hashtbl.replace seen key conn.conn_from_port.loc;
                  [
                    errorf ~sm_name:scope conn.conn_from_port.loc
                      "duplicate output connection on %s.%s[%d] (first at \
                       %s:%d:%d)"
                      inst port n prev_loc.Ast.file prev_loc.line prev_loc.col;
                  ]
              | None ->
                  Hashtbl.replace seen key conn.conn_from_port.loc;
                  [])
          | _ -> [])
      | None -> [])
    connections

let check_output_counts ~scope tu_env connections =
  let counts = Hashtbl.create 16 in
  List.iter
    (fun conn_ann ->
      let conn : Ast.connection = (Ast.unannotate conn_ann).Ast.data in
      let from_pid = conn.conn_from_port.data in
      let inst = Ast.qual_ident_to_string from_pid.pid_component.data in
      let port = from_pid.pid_port.data in
      let key = inst ^ "." ^ port in
      let loc = conn.conn_from_port.loc in
      let prev = Option.value ~default:(0, loc) (Hashtbl.find_opt counts key) in
      Hashtbl.replace counts key (fst prev + 1, loc))
    connections;
  Hashtbl.fold
    (fun key (count, loc) acc ->
      match String.split_on_char '.' key with
      | [ inst; port ] -> (
          match resolve_instance_comp tu_env inst with
          | Some comp -> (
              match port_size tu_env comp port with
              | Some sz when count > sz ->
                  errorf ~sm_name:scope loc
                    "too many connections on output port %s.%s (%d \
                     connections, port size %d)"
                    inst port count sz
                  :: acc
              | _ -> acc)
          | None -> acc)
      | _ -> acc)
    counts []

let check_direct_connections ~scope tu_env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_connection_graph (Graph_direct d) ->
          let per_conn_diags =
            List.concat_map
              (fun conn_ann ->
                let conn : Ast.connection =
                  (Ast.unannotate conn_ann).Ast.data
                in
                let type_diags = check_direct_connection ~scope tu_env conn in
                let idx_diags =
                  (match conn.conn_from_index with
                    | Some idx -> check_port_index ~scope tu_env idx "source"
                    | None -> [])
                  @
                  match conn.conn_to_index with
                  | Some idx -> check_port_index ~scope tu_env idx "target"
                  | None -> []
                in
                type_diags @ idx_diags)
              d.graph_connections
          in
          per_conn_diags
          @ check_duplicate_outputs ~scope tu_env d.graph_connections
          @ check_output_counts ~scope tu_env d.graph_connections
      | _ -> [])
    members

(* ── Topology instance collection ─────────────────────────────────── *)

let collect_topo_instances tu_env members =
  let tbl = Hashtbl.create 8 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_comp_instance ci ->
          let name = Ast.qual_ident_to_string ci.ci_instance.data in
          Hashtbl.replace tbl name ci.ci_instance.loc
      | Ast.Topo_spec_top_import qi -> (
          let topo_name = Ast.qual_ident_to_string qi.data in
          match SMap.find_opt topo_name tu_env.topologies with
          | Some imported ->
              List.iter
                (fun iann ->
                  match (Ast.unannotate iann).Ast.data with
                  | Ast.Topo_spec_comp_instance ici
                    when ici.ci_visibility = `Public ->
                      let name =
                        Ast.qual_ident_to_string ici.ci_instance.data
                      in
                      if not (Hashtbl.mem tbl name) then
                        Hashtbl.replace tbl name ici.ci_instance.loc
                  | _ -> ())
                imported.topo_members
          | None -> ())
      | _ -> ())
    members;
  tbl

let check_connection_instance_refs ~scope topo_instances members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_connection_graph (Graph_pattern p) ->
          let src = Ast.qual_ident_to_string p.pattern_source.data in
          let src_diag =
            if not (Hashtbl.mem topo_instances src) then
              [
                errorf ~sm_name:scope p.pattern_source.loc
                  "instance '%s' not in topology" src;
              ]
            else []
          in
          let tgt_diags =
            List.concat_map
              (fun (qi : Ast.qual_ident Ast.node) ->
                let name = Ast.qual_ident_to_string qi.data in
                if not (Hashtbl.mem topo_instances name) then
                  [
                    errorf ~sm_name:scope qi.loc "instance '%s' not in topology"
                      name;
                  ]
                else [])
              p.pattern_targets
          in
          src_diag @ tgt_diags
      | Ast.Topo_spec_connection_graph (Graph_direct d) ->
          List.concat_map
            (fun ann ->
              let conn : Ast.connection = (Ast.unannotate ann).Ast.data in
              let from_inst = conn.conn_from_port.data.pid_component in
              let to_inst = conn.conn_to_port.data.pid_component in
              let from_name = Ast.qual_ident_to_string from_inst.data in
              let to_name = Ast.qual_ident_to_string to_inst.data in
              (if not (Hashtbl.mem topo_instances from_name) then
                 [
                   errorf ~sm_name:scope from_inst.loc
                     "instance '%s' not in topology" from_name;
                 ]
               else [])
              @
              if not (Hashtbl.mem topo_instances to_name) then
                [
                  errorf ~sm_name:scope to_inst.loc
                    "instance '%s' not in topology" to_name;
                ]
              else [])
            d.graph_connections
      | _ -> [])
    members

(* ── Telemetry packet validation ──────────────────────────────────── *)

let check_duplicate_packet_set_names ~scope members =
  let seen = Hashtbl.create 4 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_tlm_packet_set ps -> (
          let name = ps.packet_set_name.data in
          match Hashtbl.find_opt seen name with
          | Some prev_loc ->
              [
                errorf ~sm_name:scope ps.packet_set_name.loc
                  "duplicate telemetry packet set '%s' (first at %s:%d:%d)" name
                  prev_loc.Ast.file prev_loc.line prev_loc.col;
              ]
          | None ->
              Hashtbl.replace seen name ps.packet_set_name.loc;
              [])
      | _ -> [])
    members

let split_channel_ref (qi : Ast.qual_ident Ast.node) =
  match qi.data with
  | Ast.Qualified (q, name) ->
      Some (Ast.qual_ident_to_string q.data, name.data, q.loc)
  | Ast.Unqualified _ -> None

let component_has_tlm_channel (comp : Ast.def_component) channel_name =
  List.exists
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_tlm_channel c -> c.tlm_name.data = channel_name
      | _ -> false)
    comp.comp_members

let collect_component_tlm_channels (comp : Ast.def_component) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_tlm_channel c -> Some c.tlm_name.data
      | _ -> None)
    comp.comp_members

let check_channel_ref ~scope tu_env topo_instances
    (qi : Ast.qual_ident Ast.node) =
  match split_channel_ref qi with
  | None -> []
  | Some (inst_name, channel_name, inst_loc) ->
      let in_topo =
        if not (Hashtbl.mem topo_instances inst_name) then
          [
            errorf ~sm_name:scope inst_loc "instance '%s' not in topology"
              inst_name;
          ]
        else []
      in
      let channel_ok =
        match resolve_instance_comp tu_env inst_name with
        | None -> []
        | Some comp ->
            if not (component_has_tlm_channel comp channel_name) then
              [
                errorf ~sm_name:scope qi.loc
                  "instance '%s' has no telemetry channel '%s'" inst_name
                  channel_name;
              ]
            else []
      in
      in_topo @ channel_ok

let check_packet_dup_names ~scope members =
  let seen = Hashtbl.create 8 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Tlm_packet pkt -> (
          let name = pkt.packet_name.data in
          match Hashtbl.find_opt seen name with
          | Some prev_loc ->
              [
                errorf ~sm_name:scope pkt.packet_name.loc
                  "duplicate packet name '%s' (first at %s:%d:%d)" name
                  prev_loc.Ast.file prev_loc.line prev_loc.col;
              ]
          | None ->
              Hashtbl.replace seen name pkt.packet_name.loc;
              [])
      | _ -> [])
    members

let check_packet_ids ~scope tu_env members =
  let seen_ids = Hashtbl.create 8 in
  let next_implicit = ref 0 in
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Tlm_packet pkt -> (
          match pkt.packet_id with
          | Some id_expr ->
              let nonneg = check_nonneg_id ~scope tu_env id_expr "packet ID" in
              let v, _ = eval_expr ~scope tu_env id_expr in
              let dup =
                match v with
                | Val_int n -> (
                    next_implicit := n + 1;
                    match Hashtbl.find_opt seen_ids n with
                    | Some prev_loc ->
                        [
                          errorf ~sm_name:scope id_expr.loc
                            "duplicate packet ID %d (first at %s:%d:%d)" n
                            prev_loc.Ast.file prev_loc.line prev_loc.col;
                        ]
                    | None ->
                        Hashtbl.replace seen_ids n id_expr.loc;
                        [])
                | _ -> []
              in
              nonneg @ dup
          | None -> (
              let implicit_id = !next_implicit in
              let loc = pkt.packet_name.loc in
              next_implicit := implicit_id + 1;
              match Hashtbl.find_opt seen_ids implicit_id with
              | Some prev_loc ->
                  Hashtbl.replace seen_ids implicit_id loc;
                  [
                    errorf ~sm_name:scope loc
                      "duplicate packet ID %d (implicit, first at %s:%d:%d)"
                      implicit_id prev_loc.Ast.file prev_loc.line prev_loc.col;
                  ]
              | None ->
                  Hashtbl.replace seen_ids implicit_id loc;
                  []))
      | _ -> [])
    members

let check_packet_groups ~scope tu_env members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Tlm_packet pkt -> (
          match pkt.packet_group with
          | Some g ->
              let nonneg =
                check_nonneg_id ~scope tu_env g "packet group level"
              in
              let v, _ = eval_expr ~scope tu_env g in
              let range =
                match v with
                | Val_int n when n > 0xFFFF_FFFF ->
                    [
                      errorf ~sm_name:scope g.loc
                        "packet group level %d out of range" n;
                    ]
                | _ -> []
              in
              nonneg @ range
          | None -> [])
      | _ -> [])
    members

let check_packet_channels ~scope tu_env topo_instances members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Tlm_packet pkt ->
          List.concat_map
            (check_channel_ref ~scope tu_env topo_instances)
            pkt.packet_channels
      | _ -> [])
    members

let collect_used_channels members =
  let used = Hashtbl.create 16 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Tlm_packet pkt ->
          List.iter
            (fun qi ->
              let key = Ast.qual_ident_to_string qi.Ast.data in
              Hashtbl.replace used key qi.loc)
            pkt.packet_channels
      | _ -> ())
    members;
  used

let check_used_and_omitted ~scope members omit =
  let used = collect_used_channels members in
  List.concat_map
    (fun qi ->
      let key = Ast.qual_ident_to_string qi.Ast.data in
      match Hashtbl.find_opt used key with
      | Some _ ->
          [
            errorf ~sm_name:scope qi.loc "channel '%s' is both used and omitted"
              key;
          ]
      | None -> [])
    omit

let check_channel_coverage ~scope tu_env topo_instances members omit =
  let used = Hashtbl.create 16 in
  List.iter
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Tlm_packet pkt ->
          List.iter
            (fun qi ->
              Hashtbl.replace used (Ast.qual_ident_to_string qi.Ast.data) ())
            pkt.packet_channels
      | _ -> ())
    members;
  let omitted = Hashtbl.create 16 in
  List.iter
    (fun qi ->
      Hashtbl.replace omitted (Ast.qual_ident_to_string qi.Ast.data) ())
    omit;
  Hashtbl.fold
    (fun inst_name inst_loc acc ->
      match resolve_instance_comp tu_env inst_name with
      | None -> acc
      | Some comp ->
          let channels = collect_component_tlm_channels comp in
          List.fold_left
            (fun acc ch ->
              let key = inst_name ^ "." ^ ch in
              if (not (Hashtbl.mem used key)) && not (Hashtbl.mem omitted key)
              then
                errorf ~sm_name:scope inst_loc
                  "channel '%s' is neither used nor omitted" key
                :: acc
              else acc)
            acc channels)
    topo_instances []

let check_tlm_packet_set ~scope tu_env topo_instances
    (ps : Ast.spec_tlm_packet_set) =
  check_packet_dup_names ~scope ps.packet_set_members
  @ check_packet_ids ~scope tu_env ps.packet_set_members
  @ check_packet_groups ~scope tu_env ps.packet_set_members
  @ check_packet_channels ~scope tu_env topo_instances ps.packet_set_members
  @ List.concat_map
      (check_channel_ref ~scope tu_env topo_instances)
      ps.packet_set_omit
  @ check_used_and_omitted ~scope ps.packet_set_members ps.packet_set_omit
  @ check_channel_coverage ~scope tu_env topo_instances ps.packet_set_members
      ps.packet_set_omit

let check_tlm_packet_sets ~scope tu_env topo_instances members =
  check_duplicate_packet_set_names ~scope members
  @ List.concat_map
      (fun ann ->
        match (Ast.unannotate ann).Ast.data with
        | Ast.Topo_spec_tlm_packet_set ps ->
            check_tlm_packet_set ~scope tu_env topo_instances ps
        | _ -> [])
      members

let matched_pairs (comp : Ast.def_component) =
  List.filter_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Comp_spec_port_matching pm ->
          Some (pm.match_port1.data, pm.match_port2.data)
      | _ -> None)
    comp.comp_members

let collect_all_direct_connections members =
  List.concat_map
    (fun ann ->
      match (Ast.unannotate ann).Ast.data with
      | Ast.Topo_spec_connection_graph (Graph_direct d) ->
          List.map
            (fun conn_ann -> (Ast.unannotate conn_ann).Ast.data)
            d.graph_connections
      | _ -> [])
    members

let count_port_connections connections inst_name port_name =
  List.fold_left
    (fun n (conn : Ast.connection) ->
      if conn.conn_unmatched then n
      else
        let from_pid = conn.conn_from_port.data in
        let to_pid = conn.conn_to_port.data in
        let from_inst = Ast.qual_ident_to_string from_pid.pid_component.data in
        let to_inst = Ast.qual_ident_to_string to_pid.pid_component.data in
        if
          (from_inst = inst_name && from_pid.pid_port.data = port_name)
          || (to_inst = inst_name && to_pid.pid_port.data = port_name)
        then n + 1
        else n)
    0 connections

let collect_port_indices ~scope tu_env connections inst_name port_name =
  List.fold_left
    (fun acc (conn : Ast.connection) ->
      if conn.conn_unmatched then acc
      else
        let from_pid = conn.conn_from_port.data in
        let to_pid = conn.conn_to_port.data in
        let from_inst = Ast.qual_ident_to_string from_pid.pid_component.data in
        let to_inst = Ast.qual_ident_to_string to_pid.pid_component.data in
        if from_inst = inst_name && from_pid.pid_port.data = port_name then
          match conn.conn_from_index with
          | Some ie -> (
              match fst (eval_expr ~scope tu_env ie) with
              | Val_int n -> n :: acc
              | _ -> acc)
          | None -> acc
        else if to_inst = inst_name && to_pid.pid_port.data = port_name then
          match conn.conn_to_index with
          | Some ie -> (
              match fst (eval_expr ~scope tu_env ie) with
              | Val_int n -> n :: acc
              | _ -> acc)
          | None -> acc
        else acc)
    [] connections

let collect_explicit_matched_indices ~scope tu_env connections inst_name
    port_name =
  List.filter_map
    (fun (conn : Ast.connection) ->
      if conn.conn_unmatched then None
      else
        let from_pid = conn.conn_from_port.data in
        let to_pid = conn.conn_to_port.data in
        let from_inst = Ast.qual_ident_to_string from_pid.pid_component.data in
        let to_inst = Ast.qual_ident_to_string to_pid.pid_component.data in
        if from_inst = inst_name && from_pid.pid_port.data = port_name then
          match conn.conn_from_index with
          | Some ie -> (
              match fst (eval_expr ~scope tu_env ie) with
              | Val_int n -> Some n
              | _ -> None)
          | None -> None
        else if to_inst = inst_name && to_pid.pid_port.data = port_name then
          match conn.conn_to_index with
          | Some ie -> (
              match fst (eval_expr ~scope tu_env ie) with
              | Val_int n -> Some n
              | _ -> None)
          | None -> None
        else None)
    connections

let collect_unmatched_indices ~scope tu_env connections inst_name port_name =
  List.filter_map
    (fun (conn : Ast.connection) ->
      if not conn.conn_unmatched then None
      else
        let from_pid = conn.conn_from_port.data in
        let to_pid = conn.conn_to_port.data in
        let from_inst = Ast.qual_ident_to_string from_pid.pid_component.data in
        let to_inst = Ast.qual_ident_to_string to_pid.pid_component.data in
        if from_inst = inst_name && from_pid.pid_port.data = port_name then
          match conn.conn_from_index with
          | Some ie -> (
              match fst (eval_expr ~scope tu_env ie) with
              | Val_int n -> Some n
              | _ -> None)
          | None -> None
        else if to_inst = inst_name && to_pid.pid_port.data = port_name then
          match conn.conn_to_index with
          | Some ie -> (
              match fst (eval_expr ~scope tu_env ie) with
              | Val_int n -> Some n
              | _ -> None)
          | None -> None
        else None)
    connections

let check_implicit_duplicate_at_matched ~scope tu_env connections inst_name
    inst_loc port1 port2 =
  (* Explicit indices on port2's matched connections imply port1 at the same
     indices via matching. Check if unmatched connections on port1 conflict. *)
  let implied_on_port1 =
    collect_explicit_matched_indices ~scope tu_env connections inst_name port2
  in
  let unmatched_on_port1 =
    collect_unmatched_indices ~scope tu_env connections inst_name port1
  in
  let implied_set = Hashtbl.create 4 in
  List.iter (fun idx -> Hashtbl.replace implied_set idx true) implied_on_port1;
  let d1 =
    List.filter_map
      (fun idx ->
        if Hashtbl.mem implied_set idx then
          Some
            (errorf ~sm_name:scope inst_loc
               "implicit duplicate connection at matched port %s.%s[%d]"
               inst_name port1 idx)
        else None)
      unmatched_on_port1
  in
  (* Reverse: explicit on port1 implies port2, check unmatched on port2 *)
  let implied_on_port2 =
    collect_explicit_matched_indices ~scope tu_env connections inst_name port1
  in
  let unmatched_on_port2 =
    collect_unmatched_indices ~scope tu_env connections inst_name port2
  in
  let implied_set2 = Hashtbl.create 4 in
  List.iter (fun idx -> Hashtbl.replace implied_set2 idx true) implied_on_port2;
  let d2 =
    List.filter_map
      (fun idx ->
        if Hashtbl.mem implied_set2 idx then
          Some
            (errorf ~sm_name:scope inst_loc
               "implicit duplicate connection at matched port %s.%s[%d]"
               inst_name port2 idx)
        else None)
      unmatched_on_port2
  in
  d1 @ d2

let check_matched_port_numbering ~scope tu_env topo_instances members =
  let connections = collect_all_direct_connections members in
  Hashtbl.fold
    (fun inst_name inst_loc acc ->
      match resolve_instance_comp tu_env inst_name with
      | None -> acc
      | Some comp ->
          let pairs = matched_pairs comp in
          List.fold_left
            (fun acc (port1, port2) ->
              let n1 = count_port_connections connections inst_name port1 in
              let n2 = count_port_connections connections inst_name port2 in
              if n1 <> n2 then
                errorf ~sm_name:scope inst_loc
                  "matched ports '%s.%s' and '%s.%s' have different connection \
                   counts (%d vs %d)"
                  inst_name port1 inst_name port2 n1 n2
                :: acc
              else
                let idx1 =
                  collect_port_indices ~scope tu_env connections inst_name port1
                  |> List.sort Int.compare
                in
                let idx2 =
                  collect_port_indices ~scope tu_env connections inst_name port2
                  |> List.sort Int.compare
                in
                if idx1 <> [] && idx2 <> [] && idx1 <> idx2 then
                  errorf ~sm_name:scope inst_loc
                    "matched ports '%s.%s' and '%s.%s' have mismatched port \
                     numbers"
                    inst_name port1 inst_name port2
                  :: acc
                else
                  acc
                  @ check_implicit_duplicate_at_matched ~scope tu_env
                      connections inst_name inst_loc port1 port2)
            acc pairs)
    topo_instances []

let check_topology ~scope ~root_env tu_env (topo : Ast.def_topology) =
  let topo_instances = collect_topo_instances tu_env topo.topo_members in
  check_member_refs ~scope ~root_env tu_env topo.topo_members
  @ check_duplicate_topo_instances ~scope topo.topo_members
  @ check_duplicate_patterns ~scope topo.topo_members
  @ check_duplicate_topo_imports ~scope topo.topo_members
  @ check_connection_instance_refs ~scope topo_instances topo.topo_members
  @ check_connection_patterns ~scope tu_env topo.topo_members
  @ check_direct_connections ~scope tu_env topo.topo_members
  @ check_tlm_packet_sets ~scope tu_env topo_instances topo.topo_members
  @ check_matched_port_numbering ~scope tu_env topo_instances topo.topo_members

(* ── Entry point ───────────────────────────────────────────────────── *)

let run ~scope tu_env members =
  let instances =
    let rec walk ~scope env members =
      List.concat_map
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Mod_def_component_instance i ->
              check_component_instance ~scope env i
          | Ast.Mod_def_module m ->
              let s = scope ^ "." ^ m.module_name.data in
              let sub =
                match SMap.find_opt m.module_name.data env.modules with
                | Some e -> e
                | None -> env
              in
              walk ~scope:s sub m.module_members
          | _ -> [])
        members
    in
    walk ~scope tu_env members
  in
  let id_conflicts = check_instance_id_conflicts ~scope tu_env members in
  let topologies =
    let rec walk ~scope ~root_env env members =
      List.concat_map
        (fun ann ->
          match (Ast.unannotate ann).Ast.data with
          | Ast.Mod_def_topology t ->
              let s = scope ^ "." ^ t.topo_name.data in
              check_topology ~scope:s ~root_env env t
          | Ast.Mod_def_module m ->
              let s = scope ^ "." ^ m.module_name.data in
              let sub =
                match SMap.find_opt m.module_name.data env.modules with
                | Some e -> e
                | None -> env
              in
              walk ~scope:s ~root_env sub m.module_members
          | _ -> [])
        members
    in
    walk ~scope ~root_env:tu_env tu_env members
  in
  instances @ id_conflicts @ topologies

(** FPP Abstract Syntax Tree.

    This AST closely follows the structure of the Scala FPP compiler's AST (see
    ~/git/fpp/compiler/lib/src/main/scala/ast/Ast.scala) but uses idiomatic
    OCaml patterns. *)

(** {1 Location Tracking} *)

type loc = { file : string; line : int; col : int }

let dummy_loc = { file = "<none>"; line = 0; col = 0 }

type 'a node = { loc : loc; data : 'a }

let node loc data = { loc; data }
let unnode n = n.data

type 'a annotated = string list * 'a * string list

let annotate ?(pre = []) ?(post = []) x = (pre, x, post)
let unannotate (_, x, _) = x

(** {1 Identifiers} *)

type ident = string

(** Qualified identifier for module paths. *)
type qual_ident =
  | Unqualified of ident node
  | Qualified of qual_ident node * ident node

(** {1 Literals and Expressions} *)

type literal =
  | Lit_int of string (* String to preserve exact representation *)
  | Lit_float of string
  | Lit_string of string
  | Lit_bool of bool

type binop = Add | Sub | Mul | Div
type unop = Minus

type expr =
  | Expr_array of expr node list
  | Expr_binop of expr node * binop * expr node
  | Expr_dot of expr node * ident node
  | Expr_ident of ident node
  | Expr_literal of literal
  | Expr_paren of expr node
  | Expr_struct of struct_member node list
  | Expr_subscript of expr node * expr node
  | Expr_unop of unop * expr node

and struct_member = { sm_name : ident node; sm_value : expr node }

(** {1 Type System} *)

type type_int = I8 | I16 | I32 | I64 | U8 | U16 | U32 | U64
type type_float = F32 | F64

type type_name =
  | Type_bool
  | Type_float of type_float
  | Type_int of type_int
  | Type_string of expr node option (* Optional size *)
  | Type_qual of qual_ident node

(** {1 Formal Parameters} *)

type param_kind = Param_value | Param_ref

type formal_param = {
  fp_kind : param_kind;
  fp_name : ident node;
  fp_type : type_name node;
}

type formal_param_list = formal_param node annotated list

(** {1 Definitions} *)

type def_abs_type = { abs_name : ident node }
(** Abstract type definition (opaque type). *)

type def_alias_type = { alias_name : ident node; alias_type : type_name node }
(** Type alias definition. *)

type def_array = {
  array_name : ident node;
  array_size : expr node;
  array_elt_type : type_name node;
  array_default : expr node option;
  array_format : string node option;
}
(** Array type definition. *)

type def_enum_constant = {
  enum_const_name : ident node;
  enum_const_value : expr node option;
}
(** Enum constant definition. *)

type def_enum = {
  enum_name : ident node;
  enum_type : type_name node option;
  enum_constants : def_enum_constant node annotated list;
  enum_default : expr node option;
}
(** Enum type definition. *)

type struct_type_member = {
  struct_mem_name : ident node;
  struct_mem_type : type_name node;
  struct_mem_size : expr node option; (* Array size if member is array *)
  struct_mem_format : string node option;
}
(** Struct member definition. *)

type def_struct = {
  struct_name : ident node;
  struct_members : struct_type_member node annotated list;
  struct_default : expr node option;
}
(** Struct type definition. *)

type def_constant = { const_name : ident node; const_value : expr node }
(** Constant definition. *)

(** {1 Port Definitions} *)

type def_port = {
  port_name : ident node;
  port_params : formal_param_list;
  port_return : type_name node option;
}
(** Port definition (the type of a port). *)

(** {1 Port Instance Specifications} *)

type queue_full = Assert | Block | Drop | Hook

(** General port kind. *)
type general_port_kind = Async_input | Guarded_input | Sync_input | Output

type port_instance_general = {
  gen_kind : general_port_kind;
  gen_name : ident node;
  gen_size : expr node option;
  gen_port : qual_ident node option; (* Port type *)
  gen_priority : expr node option;
  gen_queue_full : queue_full node option;
}
(** General port instance. *)

(** Special port kind. *)
type special_port_kind =
  | Command_recv
  | Command_reg
  | Command_resp
  | Event
  | Param_get
  | Param_set
  | Product_get
  | Product_recv
  | Product_request
  | Product_send
  | Telemetry
  | Text_event
  | Time_get

(** Special input kind for special ports. *)
type special_input_kind = Async | Guarded | Sync

type port_instance_special = {
  special_input_kind : special_input_kind option;
  special_kind : special_port_kind;
  special_name : ident node;
  special_priority : expr node option;
  special_queue_full : queue_full node option;
}
(** Special port instance. *)

(** Port instance specification (general or special). *)
type spec_port_instance =
  | Port_general of port_instance_general
  | Port_special of port_instance_special

type spec_internal_port = {
  internal_name : ident node;
  internal_params : formal_param_list;
  internal_priority : expr node option;
  internal_queue_full : queue_full node option;
}
(** Internal port specification. *)

type spec_port_matching = { match_port1 : ident node; match_port2 : ident node }
(** Port matching specification. *)

(** {1 Command Specification} *)

type command_kind = Command_async | Command_guarded | Command_sync

type spec_command = {
  cmd_kind : command_kind;
  cmd_name : ident node;
  cmd_params : formal_param_list;
  cmd_opcode : expr node option;
  cmd_priority : expr node option;
  cmd_queue_full : queue_full node option;
}

(** {1 Parameter Specification} *)

type spec_param = {
  param_name : ident node;
  param_type : type_name node;
  param_default : expr node option;
  param_id : expr node option;
  param_set_opcode : expr node option;
  param_save_opcode : expr node option;
  param_external : bool;
}

(** {1 Telemetry Specification} *)

type tlm_update = On_change | Always
type limit_kind = Red | Orange | Yellow
type tlm_limit = limit_kind node * expr node

type spec_tlm_channel = {
  tlm_name : ident node;
  tlm_type : type_name node;
  tlm_id : expr node option;
  tlm_update : tlm_update option;
  tlm_format : string node option;
  tlm_low : tlm_limit list;
  tlm_high : tlm_limit list;
}

(** {1 Event Specification} *)

type event_severity =
  | Activity_high
  | Activity_low
  | Command
  | Diagnostic
  | Fatal
  | Warning_high
  | Warning_low

type event_throttle = {
  throttle_count : expr node;
  throttle_every : expr node option;
}

type spec_event = {
  event_name : ident node;
  event_params : formal_param_list;
  event_severity : event_severity;
  event_id : expr node option;
  event_format : string node;
  event_throttle : event_throttle option;
}

(** {1 Data Product Specifications} *)

type spec_container = {
  container_name : ident node;
  container_id : expr node option;
  container_default_priority : expr node option;
}

type spec_record = {
  record_name : ident node;
  record_type : type_name node;
  record_array : bool;
  record_id : expr node option;
}

(** {1 State Machine Definitions} *)

type transition_expr = {
  trans_actions : ident node list;
  trans_target : qual_ident node;
}
(** Transition expression. *)

(** Transition or do-action. *)
type transition_or_do =
  | Transition of transition_expr node
  | Do of ident node list (* Just actions, no target *)

(** State member. *)
type state_member =
  | State_def_choice of def_choice
  | State_def_state of def_state
  | State_entry of ident node list
  | State_exit of ident node list
  | State_initial of transition_expr node
  | State_transition of spec_state_transition
  | State_include of string node

and spec_state_transition = {
  st_signal : ident node;
  st_guard : ident node option;
  st_action : transition_or_do;
}

and def_choice = {
  choice_name : ident node;
  choice_members : choice_member list;
}

and choice_member =
  | Choice_if of
      ident node option * transition_expr node (* guard * transition *)
  | Choice_else of transition_expr node

and def_state = {
  state_name : ident node;
  state_members : state_member node annotated list;
}

type def_action = {
  action_name : ident node;
  action_type : type_name node option;
}
(** Action definition. *)

type def_guard = { guard_name : ident node; guard_type : type_name node option }
(** Guard definition. *)

type def_signal = {
  signal_name : ident node;
  signal_type : type_name node option;
}
(** Signal definition. *)

type spec_initial_transition = transition_expr node
(** Initial transition specification. *)

(** State machine member. *)
type state_machine_member =
  | Sm_def_abs_type of def_abs_type
  | Sm_def_action of def_action
  | Sm_def_alias_type of def_alias_type
  | Sm_def_array of def_array
  | Sm_def_choice of def_choice
  | Sm_def_constant of def_constant
  | Sm_def_enum of def_enum
  | Sm_def_guard of def_guard
  | Sm_def_signal of def_signal
  | Sm_def_state of def_state
  | Sm_def_struct of def_struct
  | Sm_initial of spec_initial_transition
  | Sm_include of string node

type def_state_machine = {
  sm_name : ident node;
  sm_members : state_machine_member node annotated list option;
}
(** State machine definition. *)

type spec_state_machine_instance = {
  smi_name : ident node;
  smi_machine : qual_ident node;
  smi_priority : expr node option;
  smi_queue_full : queue_full node option;
}
(** State machine instance. *)

(** {1 Component Definitions} *)

type component_kind = Active | Passive | Queued

(** Component member. *)
type component_member =
  | Comp_def_abs_type of def_abs_type
  | Comp_def_alias_type of def_alias_type
  | Comp_def_array of def_array
  | Comp_def_constant of def_constant
  | Comp_def_enum of def_enum
  | Comp_def_state_machine of def_state_machine
  | Comp_def_struct of def_struct
  | Comp_spec_command of spec_command
  | Comp_spec_container of spec_container
  | Comp_spec_event of spec_event
  | Comp_spec_internal_port of spec_internal_port
  | Comp_spec_param of spec_param
  | Comp_spec_port_instance of spec_port_instance
  | Comp_spec_port_matching of spec_port_matching
  | Comp_spec_record of spec_record
  | Comp_spec_sm_instance of spec_state_machine_instance
  | Comp_spec_tlm_channel of spec_tlm_channel
  | Comp_spec_include of string node
  | Comp_spec_import_interface of qual_ident node

type def_component = {
  comp_kind : component_kind;
  comp_name : ident node;
  comp_members : component_member node annotated list;
}
(** Component definition. *)

(** {1 Component Instance Definitions} *)

type spec_init = { init_phase : expr node; init_code : string node }

type def_component_instance = {
  inst_name : ident node;
  inst_component : qual_ident node;
  inst_base_id : expr node;
  inst_impl_type : string node option;
  inst_file : string node option;
  inst_queue_size : expr node option;
  inst_stack_size : expr node option;
  inst_priority : expr node option;
  inst_cpu : expr node option;
  inst_init : spec_init node annotated list;
}

(** {1 Topology Definitions} *)

type port_instance_id = {
  pid_component : qual_ident node;
  pid_port : ident node;
}
(** Port instance identifier in connections. *)

type connection = {
  conn_unmatched : bool;
  conn_from_port : port_instance_id node;
  conn_from_index : expr node option;
  conn_to_port : port_instance_id node;
  conn_to_index : expr node option;
}
(** Connection between ports. *)

(** Connection graph kind. *)
type graph_pattern_kind =
  | Pattern_command
  | Pattern_event
  | Pattern_health
  | Pattern_param
  | Pattern_telemetry
  | Pattern_text_event
  | Pattern_time

(** Connection graph specification. *)
type spec_connection_graph =
  | Graph_direct of {
      graph_name : ident node;
      graph_connections : connection node annotated list;
    }
  | Graph_pattern of {
      pattern_kind : graph_pattern_kind;
      pattern_source : qual_ident node;
      pattern_targets : qual_ident node list;
    }

type spec_comp_instance = {
  ci_instance : qual_ident node;
  ci_visibility : [ `Public | `Private ];
}
(** Component instance reference in topology. *)

type tlm_packet = {
  packet_name : ident node;
  packet_id : expr node option;
  packet_group : expr node option;
  packet_channels : qual_ident node list;
}
(** Telemetry packet for packet sets. *)

(** Telemetry packet set member. *)
type tlm_packet_set_member =
  | Tlm_packet of tlm_packet
  | Tlm_include of string node

type spec_tlm_packet_set = {
  packet_set_name : ident node;
  packet_set_members : tlm_packet_set_member node annotated list;
  packet_set_omit : qual_ident node list;
}
(** Telemetry packet set. *)

(** Topology member. *)
type topology_member =
  | Topo_spec_comp_instance of spec_comp_instance
  | Topo_spec_connection_graph of spec_connection_graph
  | Topo_spec_include of string node
  | Topo_spec_tlm_packet_set of spec_tlm_packet_set
  | Topo_spec_top_import of qual_ident node

type def_topology = {
  topo_name : ident node;
  topo_members : topology_member node annotated list;
}
(** Topology definition. *)

(** {1 Location Specifiers} *)

type loc_spec_kind =
  | Loc_component
  | Loc_component_instance
  | Loc_constant
  | Loc_interface
  | Loc_port
  | Loc_state_machine
  | Loc_topology
  | Loc_type
  | Loc_dictionary_type

type spec_loc = {
  loc_kind : loc_spec_kind;
  loc_name : qual_ident node;
  loc_path : string node;
}

(** {1 Interface Definitions} *)

(** Interface member. *)
type interface_member =
  | Intf_spec_port_instance of spec_port_instance
  | Intf_spec_import of qual_ident node

type def_interface = {
  intf_name : ident node;
  intf_members : interface_member node annotated list;
}
(** Interface definition. *)

(** {1 Module Definitions} *)

(** Module member (top-level or nested in modules). *)
type module_member =
  | Mod_def_abs_type of def_abs_type
  | Mod_def_alias_type of def_alias_type
  | Mod_def_array of def_array
  | Mod_def_component of def_component
  | Mod_def_component_instance of def_component_instance
  | Mod_def_constant of def_constant
  | Mod_def_enum of def_enum
  | Mod_def_interface of def_interface
  | Mod_def_module of def_module
  | Mod_def_port of def_port
  | Mod_def_state_machine of def_state_machine
  | Mod_def_struct of def_struct
  | Mod_def_topology of def_topology
  | Mod_spec_include of string node
  | Mod_spec_loc of spec_loc

and def_module = {
  module_name : ident node;
  module_members : module_member node annotated list;
}
(** Module definition. *)

(** {1 Translation Unit} *)

type translation_unit = { tu_members : module_member node annotated list }
(** The top-level structure: a list of module members. *)

(** {1 Utilities} *)

let qual_ident_to_list qi =
  let rec go acc = function
    | Unqualified id -> id :: acc
    | Qualified (q, id) -> go (id :: acc) q.data
  in
  go [] qi

let qual_ident_to_string qi =
  String.concat "." (List.map unnode (qual_ident_to_list qi))

let qual_ident_of_list = function
  | [] -> invalid_arg "qual_ident_of_list: empty list"
  | id :: rest ->
      List.fold_left
        (fun acc id -> Qualified (node id.loc acc, id))
        (Unqualified id) rest

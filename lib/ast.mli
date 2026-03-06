(** FPP Abstract Syntax Tree.

    This module defines the abstract syntax tree for
    {{:https://nasa.github.io/fpp/fpp-users-guide.html}FPP} (F Prime Prime), the
    modeling language for NASA's F Prime flight software framework. The AST
    closely mirrors the
    {{:https://github.com/nasa/fpp/tree/main/compiler/lib/src/main/scala/fpp/compiler/ast}Scala
     reference implementation} but uses idiomatic OCaml patterns.

    The AST supports the full FPP language including:
    - Components (active, passive, queued)
    - Ports, commands, events, telemetry, parameters
    - Data products and state machines
    - Topologies and component instances
    - Type definitions (enums, structs, arrays) *)

(** {1:loc Location Tracking} *)

type loc = { file : string; line : int; col : int }
(** Source location. *)

val dummy_loc : loc
(** [dummy_loc] is a placeholder location for synthesized nodes. *)

type 'a node = { loc : loc; data : 'a }
(** Node with location. *)

val node : loc -> 'a -> 'a node
(** [node loc data] is a node with the given location and data. *)

val unnode : 'a node -> 'a
(** [unnode n] is the data from node [n]. *)

type 'a annotated = string list * 'a * string list
(** Pre and post comments. *)

val annotate : ?pre:string list -> ?post:string list -> 'a -> 'a annotated
(** [annotate ?pre ?post x] is [x] wrapped with optional pre and post
    annotations. *)

val unannotate : 'a annotated -> 'a
(** [unannotate a] is the value from annotated triple [a]. *)

(** {1:ident Identifiers} *)

type ident = string

type qual_ident =
  | Unqualified of ident node
  | Qualified of qual_ident node * ident node

(** {1:expr Literals and Expressions} *)

type literal =
  | Lit_int of string
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

(** {1:types Type System} *)

type type_int = I8 | I16 | I32 | I64 | U8 | U16 | U32 | U64
type type_float = F32 | F64

type type_name =
  | Type_bool
  | Type_float of type_float
  | Type_int of type_int
  | Type_string of expr node option
  | Type_qual of qual_ident node

(** {1:params Formal Parameters} *)

type param_kind = Param_value | Param_ref

type formal_param = {
  fp_kind : param_kind;
  fp_name : ident node;
  fp_type : type_name node;
}

type formal_param_list = formal_param node annotated list

(** {1:defs Definitions} *)

type def_abs_type = { abs_name : ident node; abs_dictionary : bool }

type def_alias_type = {
  alias_name : ident node;
  alias_type : type_name node;
  alias_dictionary : bool;
}

type def_array = {
  array_name : ident node;
  array_size : expr node;
  array_elt_type : type_name node;
  array_default : expr node option;
  array_format : string node option;
  array_dictionary : bool;
}

type def_enum_constant = {
  enum_const_name : ident node;
  enum_const_value : expr node option;
}

type def_enum = {
  enum_name : ident node;
  enum_type : type_name node option;
  enum_constants : def_enum_constant node annotated list;
  enum_default : expr node option;
  enum_dictionary : bool;
}

type struct_type_member = {
  struct_mem_name : ident node;
  struct_mem_type : type_name node;
  struct_mem_size : expr node option;
  struct_mem_format : string node option;
}

type def_struct = {
  struct_name : ident node;
  struct_members : struct_type_member node annotated list;
  struct_default : expr node option;
  struct_dictionary : bool;
}

type def_constant = {
  const_name : ident node;
  const_value : expr node;
  const_dictionary : bool;
}

(** {1:ports Port Definitions} *)

type def_port = {
  port_name : ident node;
  port_params : formal_param_list;
  port_return : type_name node option;
}

type queue_full = Assert | Block | Drop | Hook
type general_port_kind = Async_input | Guarded_input | Sync_input | Output

type port_instance_general = {
  gen_kind : general_port_kind;
  gen_name : ident node;
  gen_size : expr node option;
  gen_port : qual_ident node option;
  gen_priority : expr node option;
  gen_queue_full : queue_full node option;
}

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

type special_input_kind = Async | Guarded | Sync

type port_instance_special = {
  special_input_kind : special_input_kind option;
  special_kind : special_port_kind;
  special_name : ident node;
  special_priority : expr node option;
  special_queue_full : queue_full node option;
}

type spec_port_instance =
  | Port_general of port_instance_general
  | Port_special of port_instance_special

type spec_internal_port = {
  internal_name : ident node;
  internal_params : formal_param_list;
  internal_priority : expr node option;
  internal_queue_full : queue_full node option;
}

type spec_port_matching = { match_port1 : ident node; match_port2 : ident node }

(** {1:cmd Command Specification} *)

type command_kind = Command_async | Command_guarded | Command_sync

type spec_command = {
  cmd_kind : command_kind;
  cmd_name : ident node;
  cmd_params : formal_param_list;
  cmd_opcode : expr node option;
  cmd_priority : expr node option;
  cmd_queue_full : queue_full node option;
}

(** {1:param Parameter Specification} *)

type spec_param = {
  param_name : ident node;
  param_type : type_name node;
  param_default : expr node option;
  param_id : expr node option;
  param_set_opcode : expr node option;
  param_save_opcode : expr node option;
  param_external : bool;
}

(** {1:tlm Telemetry Specification} *)

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

(** {1:event Event Specification} *)

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

(** {1:dp Data Products} *)

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

(** {1:sm State Machines} *)

type transition_expr = {
  trans_actions : ident node list;
  trans_target : qual_ident node;
}

type transition_or_do =
  | Transition of transition_expr node
  | Do of ident node list

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
  | Choice_if of ident node option * transition_expr node
  | Choice_else of transition_expr node

and def_state = {
  state_name : ident node;
  state_members : state_member node annotated list;
}

type def_action = {
  action_name : ident node;
  action_type : type_name node option;
}

type def_guard = { guard_name : ident node; guard_type : type_name node option }

type def_signal = {
  signal_name : ident node;
  signal_type : type_name node option;
}

type spec_initial_transition = transition_expr node

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

type spec_state_machine_instance = {
  smi_name : ident node;
  smi_machine : qual_ident node;
  smi_priority : expr node option;
  smi_queue_full : queue_full node option;
}

(** {1:comp Components} *)

type component_kind = Active | Passive | Queued

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

(** {1:inst Component Instances} *)

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

(** {1:topo Topology} *)

type port_instance_id = {
  pid_component : qual_ident node;
  pid_port : ident node;
}

type connection = {
  conn_unmatched : bool;
  conn_from_port : port_instance_id node;
  conn_from_index : expr node option;
  conn_to_port : port_instance_id node;
  conn_to_index : expr node option;
}

type graph_pattern_kind =
  | Pattern_command
  | Pattern_event
  | Pattern_health
  | Pattern_param
  | Pattern_telemetry
  | Pattern_text_event
  | Pattern_time

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

type tlm_packet = {
  packet_name : ident node;
  packet_id : expr node option;
  packet_group : expr node;
  packet_channels : qual_ident node list;
}

type tlm_packet_set_member =
  | Tlm_packet of tlm_packet
  | Tlm_include of string node

type spec_tlm_packet_set = {
  packet_set_name : ident node;
  packet_set_members : tlm_packet_set_member node annotated list;
  packet_set_omit : qual_ident node list;
}

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

(** {1:locspec Location Specifiers} *)

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

(** {1:intf Interfaces} *)

type interface_member =
  | Intf_spec_port_instance of spec_port_instance
  | Intf_spec_import of qual_ident node

type def_interface = {
  intf_name : ident node;
  intf_members : interface_member node annotated list;
}

(** {1:mod Modules} *)

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

(** {1:tu Translation Unit} *)

type translation_unit = { tu_members : module_member node annotated list }

(** {1:util Utilities} *)

val qual_ident_to_list : qual_ident -> ident node list
(** [qual_ident_to_list qi] is the list of identifier nodes in [qi]. *)

val qual_ident_to_string : qual_ident -> string
(** [qual_ident_to_string qi] is the dot-separated string for [qi]. *)

val qual_ident_of_list : ident node list -> qual_ident
(** [qual_ident_of_list ids] is a qualified identifier from the list [ids]. *)

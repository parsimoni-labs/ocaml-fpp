(** FPP Grammar - Menhir parser for F Prime Prime language.

    This parser produces an AST that closely follows the structure of the
    Scala FPP compiler's AST. *)

%{
open Ast

let mk_loc startpos =
  let open Lexing in
  { Ast.file = startpos.pos_fname;
    line = startpos.pos_lnum;
    col = startpos.pos_cnum - startpos.pos_bol }

let node startpos data = { Ast.loc = mk_loc startpos; data }
%}

%token <string> IDENT
%token <string> INT
%token <string> FLOAT
%token <string> STRING
%token <bool> BOOL
%token <string> PRIM_TYPE
%token <string> ANNOTATION_PRE ANNOTATION_POST

%token ACTIVE PASSIVE QUEUED
%token ACTION ARRAY CHOICE COMMAND COMPONENT CONNECTIONS CONSTANT CONTAINER
%token DEFAULT DICTIONARY DO ELSE ENTER ENTRY ENUM EVENT EXIT EXTERNAL GUARD HEALTH IF
%token IMPORT INCLUDE INITIAL INPUT INSTANCE INTERFACE INTERNAL
%token LOCATE MATCH MODULE OPCODE OUTPUT PACKET PACKETS PARAM PHASE PORT PRIORITY
%token PRIVATE PRODUCT PUBLIC RECORD RECV REG REQUEST RESP SAVE SEND
%token SET GET SEVERITY SIGNAL SIZE STATE STRUCT TELEMETRY TEXT THROTTLE
%token TIME TOPOLOGY TYPE UNMATCHED UPDATE WITH
%token ASYNC SYNC GUARDED
%token FATAL WARNING ACTIVITY DIAGNOSTIC HIGH LOW
%token ALWAYS CHANGE ON
%token RED ORANGE YELLOW
%token ASSERT AT BASE BLOCK CPU DROP EVERY FORMAT GROUP HOOK ID MACHINE OMIT QUEUE REF SECONDS STACK STRING_KW
%token LBRACE RBRACE LBRACKET RBRACKET LPAREN RPAREN
%token COLON COMMA DOT EQUALS ARROW PLUS MINUS STAR SLASH
%token EOF

(* Phantom token for precedence: empty optional productions are marked
   PREC_BELOW so that "shift the clause token" always wins. *)
%token PREC_BELOW
%nonassoc PREC_BELOW
%nonassoc SIZE FORMAT TIME TEXT STATE HOOK DROP BLOCK TYPE ARRAY

%left PLUS MINUS
%left STAR SLASH
%nonassoc UMINUS
%nonassoc LBRACKET DOT

%start <Ast.translation_unit> translation_unit

%%

translation_unit:
  ms = list(annotated_module_member) EOF
  { { tu_members = ms } }

(* ========== Annotations ========== *)

annotation_pre:
  | { [] }
  | a = ANNOTATION_PRE rest = annotation_pre { a :: rest }

annotation_post:
  | { [] }
  | a = ANNOTATION_POST rest = annotation_post { a :: rest }

annotated(X):
  pre = annotation_pre x = X post = annotation_post
  { (pre, x, post) }

annotated_module_member:
  pre = annotation_pre m = module_member post = annotation_post
  { (pre, m, post) }

(* ========== Identifiers ========== *)

(* Some FPP keywords can also be used as identifiers in certain contexts.
   This is the list of contextual keywords that are allowed as identifiers. *)
contextual_keyword:
  | ENTRY { "entry" }
  | EXIT { "exit" }
  | STATE { "state" }
  | ACTION { "action" }
  | GUARD { "guard" }
  | SIGNAL { "signal" }
  | MACHINE { "machine" }
  | PHASE { "phase" }
  | FORMAT { "format" }
  | ID { "id" }
  | SIZE { "size" }
  | TIME { "time" }
  | ON { "on" }
  | CHANGE { "change" }
  | HIGH { "high" }
  | LOW { "low" }
  | RED { "red" }
  | ORANGE { "orange" }
  | YELLOW { "yellow" }
  | ALWAYS { "always" }
  | BLOCK { "block" }
  | DROP { "drop" }
  | HOOK { "hook" }
  | BASE { "base" }
  | CPU { "cpu" }
  | STACK { "stack" }
  | QUEUE { "queue" }
  | GROUP { "group" }
  | TEXT { "text" }
  | GET { "get" }
  | SET { "set" }
  | SEND { "send" }
  | RECV { "recv" }
  | RESP { "resp" }
  | REG { "reg" }
  | SAVE { "save" }
  | SECONDS { "seconds" }

(* An identifier can be a regular IDENT or a contextual keyword *)
ident:
  | s = IDENT { node $startpos s }
  | s = contextual_keyword { node $startpos s }

qual_ident:
  | i = ident { Unqualified i }
  | q = qual_ident DOT i = ident { Qualified (node $startpos(q) q, i) }

qual_ident_node:
  q = qual_ident { node $startpos q }

(* ========== Literals and Expressions ========== *)

literal:
  | n = INT { Lit_int n }
  | f = FLOAT { Lit_float f }
  | s = STRING { Lit_string s }
  | b = BOOL { Lit_bool b }

expr_node:
  e = expr { node $startpos e }

expr:
  | l = literal { Expr_literal l }
  | i = ident { Expr_ident i }
  | LPAREN e = expr_node RPAREN { Expr_paren e }
  | LBRACKET es = loption(trailing_comma_expr_list) RBRACKET { Expr_array es }
  | LBRACE ms = loption(trailing_comma_struct_init_list) RBRACE { Expr_struct ms }
  | e1 = expr_node PLUS e2 = expr_node { Expr_binop (e1, Add, e2) }
  | e1 = expr_node MINUS e2 = expr_node { Expr_binop (e1, Sub, e2) }
  | e1 = expr_node STAR e2 = expr_node { Expr_binop (e1, Mul, e2) }
  | e1 = expr_node SLASH e2 = expr_node { Expr_binop (e1, Div, e2) }
  | MINUS e = expr_node %prec UMINUS { Expr_unop (Minus, e) }
  | e = expr_node LBRACKET i = expr_node RBRACKET { Expr_subscript (e, i) }
  | e = expr_node DOT i = ident { Expr_dot (e, i) }

struct_member_init:
  n = ident EQUALS e = expr_node
  { node $startpos { sm_name = n; sm_value = e } }

(* Comma-separated lists with trailing comma support *)
trailing_comma_expr_list:
  | e = expr_node { [e] }
  | e = expr_node COMMA es = loption(trailing_comma_expr_list) { e :: es }

trailing_comma_struct_init_list:
  | m = struct_member_init { [m] }
  | m = struct_member_init COMMA ms = loption(trailing_comma_struct_init_list) { m :: ms }
  | m = struct_member_init ms = trailing_comma_struct_init_list { m :: ms }

(* ========== Type System ========== *)

type_name_node:
  t = type_name { node $startpos t }

type_name:
  | p = PRIM_TYPE {
      match p with
      | "U8" -> Type_int U8 | "U16" -> Type_int U16
      | "U32" -> Type_int U32 | "U64" -> Type_int U64
      | "I8" -> Type_int I8 | "I16" -> Type_int I16
      | "I32" -> Type_int I32 | "I64" -> Type_int I64
      | "F32" -> Type_float F32 | "F64" -> Type_float F64
      | "bool" -> Type_bool
      | _ -> Type_int U32  (* fallback *)
    }
  | STRING_KW %prec PREC_BELOW { Type_string None }
  | STRING_KW SIZE e = expr_node { Type_string (Some e) }
  | q = qual_ident_node { Type_qual q }

(* ========== Formal Parameters ========== *)

param_kind:
  | { Param_value }
  | REF { Param_ref }

formal_param:
  k = param_kind n = ident COLON t = type_name_node
  { node $startpos { fp_kind = k; fp_name = n; fp_type = t } }

(* Formal parameters can be separated by commas or newlines.
   Post-annotations (@<) may appear after a comma (FPP convention). *)
formal_param_list:
  | p = annotated(formal_param) { [p] }
  | pre = annotation_pre fp = formal_param COMMA post = annotation_post
    ps = loption(formal_param_list)
    { (pre, fp, post) :: ps }
  | p = annotated(formal_param) ps = formal_param_list { p :: ps }

formal_params:
  | LPAREN RPAREN { [] }
  | LPAREN ps = formal_param_list RPAREN { ps }

formal_params_opt:
  | { [] }
  | ps = formal_params { ps }

(* ========== Common Clauses ========== *)

priority_clause: PRIORITY e = expr_node { e }
opcode_clause: OPCODE e = expr_node { e }
default_clause: DEFAULT e = expr_node { e }
id_clause: ID e = expr_node { e }
format_clause: FORMAT s = STRING { node $startpos s }

queue_full:
  | ASSERT { Assert }
  | BLOCK { Block }
  | DROP { Drop }
  | HOOK { Hook }

queue_full_clause:
  q = queue_full { node $startpos q }

array_size: LBRACKET n = expr_node RBRACKET { n }

(* ========== Port Definitions ========== *)

port_def:
  PORT n = ident ps = formal_params_opt ret = option(preceded(ARROW, type_name_node))
  { node $startpos (Mod_def_port { port_name = n; port_params = ps; port_return = ret }) }

(* ========== Port Instance Specifications ========== *)

general_port_kind:
  | ASYNC INPUT { Async_input }
  | GUARDED INPUT { Guarded_input }
  | SYNC INPUT { Sync_input }
  | INPUT { Sync_input }  (* default to sync *)
  | OUTPUT { Output }

qual_ident_node_opt:
  | %prec PREC_BELOW { None }
  | q = qual_ident_node { Some q }

port_instance_general:
  k = general_port_kind PORT n = ident COLON sz = option(array_size)
  pt = qual_ident_node_opt pri = option(priority_clause) qf = option(queue_full_clause)
  { Port_general {
      gen_kind = k;
      gen_name = n;
      gen_size = sz;
      gen_port = pt;
      gen_priority = pri;
      gen_queue_full = qf;
    } }

special_port_kind:
  | COMMAND RECV { Command_recv }
  | COMMAND RESP { Command_resp }
  | COMMAND REG { Command_reg }
  | EVENT { Event }
  | TEXT EVENT { Text_event }
  | TIME GET { Time_get }
  | TELEMETRY { Telemetry }
  | PARAM GET { Param_get }
  | PARAM SET { Param_set }
  | PRODUCT GET { Product_get }
  | PRODUCT RECV { Product_recv }
  | PRODUCT REQUEST { Product_request }
  | PRODUCT SEND { Product_send }

(* Special port kinds that don't conflict with other specs.
   COMMAND RECV/RESP/REG are excluded - they conflict with SYNC/ASYNC/GUARDED COMMAND
   and must be handled explicitly in comp_member. *)
special_port_kind_no_conflict:
  | TEXT EVENT { Text_event }
  | TIME GET { Time_get }
  | PRODUCT GET { Product_get }
  | PRODUCT RECV { Product_recv }
  | PRODUCT REQUEST { Product_request }
  | PRODUCT SEND { Product_send }

(* Port instance special - inlined to avoid conflicts with option(special_input_kind) *)
(* Without input kind prefix *)
port_instance_special_no_prefix:
  k = special_port_kind PORT n = ident
  pri = option(priority_clause) qf = option(queue_full_clause)
  { Port_special {
      special_input_kind = None;
      special_kind = k;
      special_name = n;
      special_priority = pri;
      special_queue_full = qf;
    } }

(* With ASYNC prefix - only for non-conflicting kinds *)
port_instance_special_async:
  ASYNC k = special_port_kind_no_conflict PORT n = ident
  pri = option(priority_clause) qf = option(queue_full_clause)
  { Port_special {
      special_input_kind = Some Async;
      special_kind = k;
      special_name = n;
      special_priority = pri;
      special_queue_full = qf;
    } }

(* With SYNC prefix - only for non-conflicting kinds *)
port_instance_special_sync:
  SYNC k = special_port_kind_no_conflict PORT n = ident
  pri = option(priority_clause) qf = option(queue_full_clause)
  { Port_special {
      special_input_kind = Some Sync;
      special_kind = k;
      special_name = n;
      special_priority = pri;
      special_queue_full = qf;
    } }

(* With GUARDED prefix - only for non-conflicting kinds *)
port_instance_special_guarded:
  GUARDED k = special_port_kind_no_conflict PORT n = ident
  pri = option(priority_clause) qf = option(queue_full_clause)
  { Port_special {
      special_input_kind = Some Guarded;
      special_kind = k;
      special_name = n;
      special_priority = pri;
      special_queue_full = qf;
    } }

spec_port_instance:
  | p = port_instance_general { p }
  | p = port_instance_special_no_prefix { p }
  | p = port_instance_special_async { p }
  | p = port_instance_special_sync { p }
  | p = port_instance_special_guarded { p }

(* Internal port *)
spec_internal_port:
  INTERNAL PORT n = ident ps = formal_params_opt
  pri = option(priority_clause) qf = option(queue_full_clause)
  { { internal_name = n;
      internal_params = ps;
      internal_priority = pri;
      internal_queue_full = qf } }

(* Port matching *)
spec_port_matching:
  MATCH p1 = ident WITH p2 = ident
  { { match_port1 = p1; match_port2 = p2 } }

(* ========== Parameter Specification ========== *)

(* Commands are inlined in comp_member to avoid conflict with COMMAND RECV/RESP/REG ports *)

set_opcode_clause: SET OPCODE e = expr_node { e }
save_opcode_clause: SAVE OPCODE e = expr_node { e }

(* Parameters are inlined in comp_member to avoid conflict with PARAM GET/SET ports *)

(* ========== Telemetry Specification ========== *)

tlm_update:
  | UPDATE ALWAYS { Always }
  | UPDATE ON CHANGE { On_change }

limit_kind:
  | RED { Red }
  | ORANGE { Orange }
  | YELLOW { Yellow }

tlm_limit:
  c = limit_kind e = expr_node
  { (node $startpos c, e) }

tlm_limits: LBRACE ls = separated_list(COMMA, tlm_limit) RBRACE { ls }
low_limits: LOW ls = tlm_limits { ls }
high_limits: HIGH ls = tlm_limits { ls }

spec_tlm_channel:
  TELEMETRY n = ident COLON t = type_name_node
  id = option(id_clause) upd = option(tlm_update) fmt = option(format_clause)
  lo = loption(low_limits) hi = loption(high_limits)
  { { tlm_name = n;
      tlm_type = t;
      tlm_id = id;
      tlm_update = upd;
      tlm_format = fmt;
      tlm_low = lo;
      tlm_high = hi } }

(* ========== Event Specification ========== *)

event_severity:
  | SEVERITY FATAL { Fatal }
  | SEVERITY WARNING HIGH { Warning_high }
  | SEVERITY WARNING LOW { Warning_low }
  | SEVERITY COMMAND { Command }
  | SEVERITY ACTIVITY HIGH { Activity_high }
  | SEVERITY ACTIVITY LOW { Activity_low }
  | SEVERITY DIAGNOSTIC { Diagnostic }

throttle_timeout: EVERY e = expr_node { e }

event_throttle:
  THROTTLE n = expr_node timeout = option(throttle_timeout)
  { { throttle_count = n; throttle_every = timeout } }

spec_event:
  EVENT n = ident ps = formal_params_opt
  sev = event_severity id = option(id_clause) fmt = format_clause
  thr = option(event_throttle)
  { { event_name = n;
      event_params = ps;
      event_severity = sev;
      event_id = id;
      event_format = fmt;
      event_throttle = thr } }

(* ========== Data Product Specifications ========== *)

default_priority_clause: DEFAULT PRIORITY e = expr_node { e }

spec_container:
  PRODUCT CONTAINER n = ident id = option(id_clause) pri = option(default_priority_clause)
  { { container_name = n;
      container_id = id;
      container_default_priority = pri } }

array_flag:
  | %prec PREC_BELOW { false }
  | ARRAY { true }

spec_record:
  PRODUCT RECORD n = ident COLON t = type_name_node arr = array_flag id = option(id_clause)
  { { record_name = n;
      record_type = t;
      record_array = arr;
      record_id = id } }

(* ========== State Machine Definitions ========== *)

(* Transition expression: actions and target *)
transition_expr:
  acts = loption(preceded(DO, ident_list)) ENTER tgt = qual_ident_node
  { node $startpos { trans_actions = acts; trans_target = tgt } }

ident_list:
  | i = ident { [i] }
  | LBRACE is = separated_nonempty_list(COMMA, ident) RBRACE { is }

(* Transition or do-action *)
transition_or_do:
  | t = transition_expr { Transition t }
  | DO acts = ident_list { Do acts }

(* State transition specification *)
spec_state_transition:
  ON sig_ = ident grd = option(preceded(IF, ident)) act = transition_or_do
  { { st_signal = sig_; st_guard = grd; st_action = act } }

(* Choice member: if/else branches *)
choice_member:
  | IF grd = option(ident) t = transition_expr { Choice_if (grd, t) }
  | ELSE t = transition_expr { Choice_else t }

(* Choice definition *)
def_choice:
  CHOICE n = ident LBRACE ms = nonempty_list(choice_member) RBRACE
  { { choice_name = n; choice_members = ms } }

(* State definition *)
state_member:
  | c = def_choice { node $startpos (State_def_choice c) }
  | s = def_state { node $startpos (State_def_state s) }
  | ENTRY DO acts = ident_list { node $startpos (State_entry acts) }
  | EXIT DO acts = ident_list { node $startpos (State_exit acts) }
  | INITIAL t = transition_expr { node $startpos (State_initial t) }
  | t = spec_state_transition { node $startpos (State_transition t) }
  | INCLUDE s = STRING { node $startpos (State_include (node $startpos s)) }

def_state:
  STATE n = ident ms = loption(delimited(LBRACE, list(annotated(state_member)), RBRACE))
  { { state_name = n; state_members = ms } }

(* State machine member *)
state_machine_member:
  | ACTION n = ident t = option(preceded(COLON, type_name_node))
    { node $startpos (Sm_def_action { action_name = n; action_type = t }) }
  | GUARD n = ident t = option(preceded(COLON, type_name_node))
    { node $startpos (Sm_def_guard { guard_name = n; guard_type = t }) }
  | SIGNAL n = ident t = option(preceded(COLON, type_name_node))
    { node $startpos (Sm_def_signal { signal_name = n; signal_type = t }) }
  | c = def_choice { node $startpos (Sm_def_choice c) }
  | s = def_state { node $startpos (Sm_def_state s) }
  | INITIAL t = transition_expr { node $startpos (Sm_initial t) }
  | INCLUDE s = STRING { node $startpos (Sm_include (node $startpos s)) }
  (* Type definitions in state machines *)
  | a = def_array { node $startpos (Sm_def_array a) }
  | c = def_constant { node $startpos (Sm_def_constant c) }
  | e = def_enum { node $startpos (Sm_def_enum e) }
  | s = def_struct { node $startpos (Sm_def_struct s) }
  | TYPE n = ident { node $startpos (Sm_def_abs_type { abs_name = n }) }
  | TYPE n = ident EQUALS t = type_name_node { node $startpos (Sm_def_alias_type { alias_name = n; alias_type = t }) }

(* State machine definition *)
def_state_machine:
  STATE MACHINE n = ident body = option(delimited(LBRACE, list(annotated(state_machine_member)), RBRACE))
  { { sm_name = n; sm_members = body } }

(* State machine instance in component *)
spec_state_machine_instance:
  STATE MACHINE INSTANCE n = ident COLON t = qual_ident_node
  pri = option(priority_clause) qf = option(queue_full_clause)
  { { smi_name = n;
      smi_machine = t;
      smi_priority = pri;
      smi_queue_full = qf } }

(* ========== Type Definitions ========== *)

def_array:
  ARRAY n = ident EQUALS LBRACKET sz = expr_node RBRACKET t = type_name_node
  def = option(default_clause) fmt = option(format_clause)
  { { array_name = n;
      array_size = sz;
      array_elt_type = t;
      array_default = def;
      array_format = fmt } }

format_clause_opt:
  | %prec PREC_BELOW { None }
  | FORMAT s = STRING { Some (node $startpos s) }

struct_type_member:
  n = ident COLON sz = option(array_size) t = type_name_node fmt = format_clause_opt
  { node $startpos {
      struct_mem_name = n;
      struct_mem_type = t;
      struct_mem_size = sz;
      struct_mem_format = fmt } }

(* Struct members can be separated by commas or newlines.
   Post-annotations (@<) may appear after a comma. *)
struct_member_list:
  | m = annotated(struct_type_member) { [m] }
  | pre = annotation_pre m = struct_type_member COMMA post = annotation_post
    ms = loption(struct_member_list)
    { (pre, m, post) :: ms }
  | m = annotated(struct_type_member) ms = struct_member_list { m :: ms }

def_struct:
  STRUCT n = ident LBRACE ms = loption(struct_member_list) RBRACE
  def = option(default_clause)
  { { struct_name = n;
      struct_members = ms;
      struct_default = def } }

def_enum_constant:
  n = ident v = option(preceded(EQUALS, expr_node))
  { node $startpos { enum_const_name = n; enum_const_value = v } }

(* Enum constants can be separated by commas or newlines.
   Post-annotations (@<) may appear after a comma. *)
enum_constant_list:
  | c = annotated(def_enum_constant) { [c] }
  | pre = annotation_pre c = def_enum_constant COMMA post = annotation_post
    cs = loption(enum_constant_list)
    { (pre, c, post) :: cs }
  | c = annotated(def_enum_constant) cs = enum_constant_list { c :: cs }

def_enum:
  ENUM n = ident t = option(preceded(COLON, type_name_node)) LBRACE
  cs = loption(enum_constant_list) RBRACE
  def = option(default_clause)
  { { enum_name = n;
      enum_type = t;
      enum_constants = cs;
      enum_default = def } }

def_constant:
  CONSTANT n = ident EQUALS e = expr_node
  { { const_name = n; const_value = e } }

(* ========== Component Definition ========== *)

component_kind:
  | PASSIVE { Passive }
  | ACTIVE { Active }
  | QUEUED { Queued }

comp_member:
  (* Port instances - general and special without input kind prefix *)
  | p = port_instance_general { node $startpos (Comp_spec_port_instance p) }
  | p = port_instance_special_no_prefix { node $startpos (Comp_spec_port_instance p) }

  (* Commands - inlined to avoid conflict with COMMAND RECV/RESP/REG ports *)
  | SYNC COMMAND n = ident ps = formal_params_opt
    op = option(opcode_clause) pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_command { cmd_kind = Command_sync; cmd_name = n;
        cmd_params = ps; cmd_opcode = op; cmd_priority = pri; cmd_queue_full = qf }) }
  | ASYNC COMMAND n = ident ps = formal_params_opt
    op = option(opcode_clause) pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_command { cmd_kind = Command_async; cmd_name = n;
        cmd_params = ps; cmd_opcode = op; cmd_priority = pri; cmd_queue_full = qf }) }
  | GUARDED COMMAND n = ident ps = formal_params_opt
    op = option(opcode_clause) pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_command { cmd_kind = Command_guarded; cmd_name = n;
        cmd_params = ps; cmd_opcode = op; cmd_priority = pri; cmd_queue_full = qf }) }

  (* Special ports with SYNC/ASYNC/GUARDED prefix and COMMAND RECV/RESP/REG kind *)
  | SYNC COMMAND RECV PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Sync;
        special_kind = Command_recv; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | SYNC COMMAND RESP PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Sync;
        special_kind = Command_resp; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | SYNC COMMAND REG PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Sync;
        special_kind = Command_reg; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | ASYNC COMMAND RECV PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Async;
        special_kind = Command_recv; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | ASYNC COMMAND RESP PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Async;
        special_kind = Command_resp; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | ASYNC COMMAND REG PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Async;
        special_kind = Command_reg; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | GUARDED COMMAND RECV PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Guarded;
        special_kind = Command_recv; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | GUARDED COMMAND RESP PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Guarded;
        special_kind = Command_resp; special_name = n; special_priority = pri; special_queue_full = qf })) }
  | GUARDED COMMAND REG PORT n = ident pri = option(priority_clause) qf = option(queue_full_clause)
    { node $startpos (Comp_spec_port_instance (Port_special { special_input_kind = Some Guarded;
        special_kind = Command_reg; special_name = n; special_priority = pri; special_queue_full = qf })) }

  (* Special ports with SYNC/ASYNC/GUARDED prefix - non-conflicting kinds *)
  | p = port_instance_special_async { node $startpos (Comp_spec_port_instance p) }
  | p = port_instance_special_sync { node $startpos (Comp_spec_port_instance p) }
  | p = port_instance_special_guarded { node $startpos (Comp_spec_port_instance p) }

  (* spec_param inlined to avoid conflict with param get/set ports *)
  | EXTERNAL PARAM n = ident COLON t = type_name_node
    def = option(default_clause) id = option(id_clause)
    setop = option(set_opcode_clause) saveop = option(save_opcode_clause)
    { node $startpos (Comp_spec_param { param_name = n; param_type = t;
        param_default = def; param_id = id; param_set_opcode = setop;
        param_save_opcode = saveop; param_external = true }) }
  | PARAM n = ident COLON t = type_name_node
    def = option(default_clause) id = option(id_clause)
    setop = option(set_opcode_clause) saveop = option(save_opcode_clause)
    { node $startpos (Comp_spec_param { param_name = n; param_type = t;
        param_default = def; param_id = id; param_set_opcode = setop;
        param_save_opcode = saveop; param_external = false }) }
  | t = spec_tlm_channel { node $startpos (Comp_spec_tlm_channel t) }
  | e = spec_event { node $startpos (Comp_spec_event e) }
  | i = spec_internal_port { node $startpos (Comp_spec_internal_port i) }
  | c = spec_container { node $startpos (Comp_spec_container c) }
  | r = spec_record { node $startpos (Comp_spec_record r) }
  | s = def_state_machine { node $startpos (Comp_def_state_machine s) }
  | i = spec_state_machine_instance { node $startpos (Comp_spec_sm_instance i) }
  | m = spec_port_matching { node $startpos (Comp_spec_port_matching m) }
  | TYPE n = ident { node $startpos (Comp_def_abs_type { abs_name = n }) }
  | TYPE n = ident EQUALS t = type_name_node { node $startpos (Comp_def_alias_type { alias_name = n; alias_type = t }) }
  | a = def_array { node $startpos (Comp_def_array a) }
  | s = def_struct { node $startpos (Comp_def_struct s) }
  | e = def_enum { node $startpos (Comp_def_enum e) }
  | c = def_constant { node $startpos (Comp_def_constant c) }
  | INCLUDE s = STRING { node $startpos (Comp_spec_include (node $startpos s)) }
  | IMPORT i = qual_ident_node { node $startpos (Comp_spec_import_interface i) }

def_component:
  k = component_kind COMPONENT n = ident LBRACE ms = list(annotated(comp_member)) RBRACE
  { { comp_kind = k;
      comp_name = n;
      comp_members = ms } }

(* ========== Interface Definition ========== *)

intf_member:
  | p = spec_port_instance { node $startpos (Intf_spec_port_instance p) }
  | IMPORT i = qual_ident_node { node $startpos (Intf_spec_import i) }

def_interface:
  INTERFACE n = ident LBRACE ms = list(annotated(intf_member)) RBRACE
  { { intf_name = n; intf_members = ms } }

(* ========== Component Instance Definition ========== *)

spec_init:
  PHASE n = expr_node s = STRING
  { node $startpos { init_phase = n; init_code = node $startpos s } }

impl_type_opt:
  | %prec PREC_BELOW { None }
  | TYPE s = STRING { Some s }

def_component_instance:
  INSTANCE n = ident COLON t = qual_ident_node BASE ID bid = expr_node
  impl = impl_type_opt at = option(preceded(AT, STRING))
  qs = option(preceded(pair(QUEUE, SIZE), expr_node))
  ss = option(preceded(pair(STACK, SIZE), expr_node))
  pri = option(priority_clause) cpu = option(preceded(CPU, expr_node))
  inits = loption(delimited(LBRACE, list(annotated(spec_init)), RBRACE))
  { { inst_name = n;
      inst_component = t;
      inst_base_id = bid;
      inst_impl_type = Option.map (fun s -> node $startpos s) impl;
      inst_file = Option.map (fun s -> node $startpos s) at;
      inst_queue_size = qs;
      inst_stack_size = ss;
      inst_priority = pri;
      inst_cpu = cpu;
      inst_init = inits } }

(* ========== Topology Definition ========== *)

(* Parse ident.ident... and split: all but last = component, last = port *)
port_instance_id:
  i = ident DOT rest = separated_nonempty_list(DOT, ident)
  { let all = i :: rest in
    let rev = List.rev all in
    let port_id = List.hd rev in
    let comp_ids = List.rev (List.tl rev) in
    let comp_qi = qual_ident_of_list comp_ids in
    node $startpos { pid_component = node $startpos comp_qi; pid_port = port_id } }

connection:
  unm = boption(UNMATCHED)
  src = port_instance_id src_idx = option(array_size)
  ARROW
  dst = port_instance_id dst_idx = option(array_size)
  { node $startpos {
      conn_unmatched = unm;
      conn_from_port = src;
      conn_from_index = src_idx;
      conn_to_port = dst;
      conn_to_index = dst_idx } }

graph_direct:
  CONNECTIONS n = ident LBRACE cs = list(annotated(connection)) RBRACE
  { Graph_direct { graph_name = n; graph_connections = cs } }

graph_pattern_kind:
  | COMMAND { Pattern_command }
  | EVENT { Pattern_event }
  | HEALTH { Pattern_health }
  | PARAM { Pattern_param }
  | TELEMETRY { Pattern_telemetry }
  | TEXT EVENT { Pattern_text_event }
  | TIME { Pattern_time }

graph_pattern:
  k = graph_pattern_kind CONNECTIONS INSTANCE src = qual_ident_node
  targets = loption(delimited(LBRACE, separated_list(COMMA, qual_ident_node), RBRACE))
  { Graph_pattern {
      pattern_kind = k;
      pattern_source = src;
      pattern_targets = targets } }

spec_connection_graph:
  | g = graph_direct { g }
  | g = graph_pattern { g }

visibility:
  | { `Public }
  | PRIVATE { `Private }
  | PUBLIC { `Public }

spec_comp_instance:
  vis = visibility INSTANCE inst = qual_ident_node
  { { ci_instance = inst; ci_visibility = vis } }

tlm_packet:
  PACKET n = ident id = option(id_clause) grp = option(preceded(GROUP, expr_node))
  LBRACE cs = list(qual_ident_node) RBRACE
  { { packet_name = n;
      packet_id = id;
      packet_group = grp;
      packet_channels = cs } }

tlm_packet_set_member:
  | p = tlm_packet { node $startpos (Tlm_packet p) }
  | INCLUDE s = STRING { node $startpos (Tlm_include (node $startpos s)) }

spec_tlm_packet_set:
  TELEMETRY PACKETS n = ident LBRACE
  ms = list(annotated(tlm_packet_set_member)) RBRACE
  om = loption(preceded(OMIT, delimited(LBRACE, list(qual_ident_node), RBRACE)))
  { { packet_set_name = n;
      packet_set_members = ms;
      packet_set_omit = om } }

topo_member:
  | c = spec_comp_instance { node $startpos (Topo_spec_comp_instance c) }
  | g = spec_connection_graph { node $startpos (Topo_spec_connection_graph g) }
  | IMPORT t = qual_ident_node { node $startpos (Topo_spec_top_import t) }
  | INCLUDE s = STRING { node $startpos (Topo_spec_include (node $startpos s)) }
  | p = spec_tlm_packet_set { node $startpos (Topo_spec_tlm_packet_set p) }

def_topology:
  TOPOLOGY n = ident LBRACE ms = list(annotated(topo_member)) RBRACE
  { { topo_name = n; topo_members = ms } }

(* ========== Location Specifiers ========== *)

loc_spec_kind:
  | COMPONENT { Loc_component }
  | INSTANCE { Loc_component_instance }
  | CONSTANT { Loc_constant }
  | DICTIONARY TYPE { Loc_dictionary_type }
  | INTERFACE { Loc_interface }
  | PORT { Loc_port }
  | STATE MACHINE { Loc_state_machine }
  | TOPOLOGY { Loc_topology }
  | TYPE { Loc_type }

spec_loc:
  LOCATE k = loc_spec_kind n = qual_ident_node AT s = STRING
  { { loc_kind = k;
      loc_name = n;
      loc_path = node $startpos s } }

(* ========== Module Definition ========== *)

module_member:
  | MODULE n = ident LBRACE ms = list(annotated_module_member) RBRACE
    { node $startpos (Mod_def_module { module_name = n; module_members = ms }) }
  | c = def_component { node $startpos (Mod_def_component c) }
  | i = def_interface { node $startpos (Mod_def_interface i) }
  | t = def_topology { node $startpos (Mod_def_topology t) }
  | i = def_component_instance { node $startpos (Mod_def_component_instance i) }
  | p = port_def { p }
  | option(DICTIONARY) TYPE n = ident { node $startpos (Mod_def_abs_type { abs_name = n }) }
  | option(DICTIONARY) TYPE n = ident EQUALS t = type_name_node { node $startpos (Mod_def_alias_type { alias_name = n; alias_type = t }) }
  | option(DICTIONARY) a = def_array { node $startpos (Mod_def_array a) }
  | option(DICTIONARY) s = def_struct { node $startpos (Mod_def_struct s) }
  | option(DICTIONARY) e = def_enum { node $startpos (Mod_def_enum e) }
  | option(DICTIONARY) c = def_constant { node $startpos (Mod_def_constant c) }
  | s = def_state_machine { node $startpos (Mod_def_state_machine s) }
  | l = spec_loc { node $startpos (Mod_spec_loc l) }
  | INCLUDE s = STRING { node $startpos (Mod_spec_include (node $startpos s)) }

%%

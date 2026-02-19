(** Shared types and utilities for translation-unit-level checks.

    Provides the TU environment type, symbol resolution, expression evaluation,
    and other helpers used across the TU check modules. This module is internal
    to the [fpp] library.

    {1:kinds Symbol kinds} *)

type symbol_kind =
  | Sk_type
  | Sk_constant
  | Sk_port
  | Sk_component
  | Sk_instance
  | Sk_topology
  | Sk_state_machine
  | Sk_module
  | Sk_interface  (** The kind of a symbol in the TU namespace. *)

val string_of_symbol_kind : symbol_kind -> string
(** [string_of_symbol_kind k] is the human-readable name of [k]. *)

(** {1:env TU environment} *)

type tu_env = {
  symbols : (symbol_kind * Ast.loc) Check_env.SMap.t;
  modules : tu_env Check_env.SMap.t;
  components : Ast.def_component Check_env.SMap.t;
  port_defs : Ast.def_port Check_env.SMap.t;
  interfaces : Ast.def_interface Check_env.SMap.t;
  topologies : Ast.def_topology Check_env.SMap.t;
  instances : Ast.def_component_instance Check_env.SMap.t;
  state_machines : Ast.def_state_machine Check_env.SMap.t;
  constants : Ast.def_constant Check_env.SMap.t;
  types : (symbol_kind * Ast.loc) Check_env.SMap.t;
  alias_targets : Ast.type_name Ast.node Check_env.SMap.t;
}
(** Translation-unit symbol environment. *)

val build_tu_env : Ast.module_member Ast.node Ast.annotated list -> tu_env
(** [build_tu_env members] walks all module members and builds a symbol
    environment recording every definition with its kind and location. *)

(** {1:resolve Symbol resolution} *)

val resolve_symbol : tu_env -> Ast.qual_ident -> (symbol_kind * Ast.loc) option
(** [resolve_symbol env qi] resolves a qualified identifier through module
    scopes, returning the symbol kind and location if found. *)

val check_symbol_as_type :
  scope:string -> tu_env -> Ast.qual_ident Ast.node -> Check_env.diagnostic list
(** [check_symbol_as_type ~scope env qi] checks that [qi] resolves to a type. *)

val check_symbol_as_constant :
  scope:string -> tu_env -> Ast.qual_ident Ast.node -> Check_env.diagnostic list
(** [check_symbol_as_constant ~scope env qi] checks that [qi] resolves to a
    constant. *)

val check_symbol_as_component :
  scope:string -> tu_env -> Ast.qual_ident Ast.node -> Check_env.diagnostic list
(** [check_symbol_as_component ~scope env qi] checks that [qi] resolves to a
    component. Reports an error if undefined. *)

val check_symbol_as_topology :
  scope:string -> tu_env -> Ast.qual_ident Ast.node -> Check_env.diagnostic list
(** [check_symbol_as_topology ~scope env qi] checks that [qi] resolves to a
    topology. Reports an error if undefined. *)

val check_symbol_as_port :
  scope:string -> tu_env -> Ast.qual_ident Ast.node -> Check_env.diagnostic list
(** [check_symbol_as_port ~scope env qi] checks that [qi] resolves to a port. *)

val check_symbol_as_state_machine :
  scope:string -> tu_env -> Ast.qual_ident Ast.node -> Check_env.diagnostic list
(** [check_symbol_as_state_machine ~scope env qi] checks that [qi] resolves to a
    state machine. *)

val check_symbol_as_instance :
  scope:string -> tu_env -> Ast.qual_ident Ast.node -> Check_env.diagnostic list
(** [check_symbol_as_instance ~scope env qi] checks that [qi] resolves to a
    component instance. *)

val check_type_name :
  scope:string -> tu_env -> Ast.type_name Ast.node -> Check_env.diagnostic list
(** [check_type_name ~scope env tn] checks that the type name [tn] refers to a
    valid type in the environment. *)

(** {1:eval Expression evaluation} *)

type eval_result =
  | Val_int of int
  | Val_float of float
  | Val_string of string
  | Val_bool of bool
  | Val_array of eval_result list
  | Val_struct of (string * eval_result) list
  | Val_unknown  (** Result of constant expression evaluation. *)

val eval_expr :
  scope:string ->
  tu_env ->
  Ast.expr Ast.node ->
  eval_result * Check_env.diagnostic list
(** [eval_expr ~scope env e] evaluates a constant expression, returning the
    value and any diagnostics. *)

val check_expr :
  scope:string -> tu_env -> Ast.expr Ast.node -> Check_env.diagnostic list
(** [check_expr ~scope env e] checks an expression for type errors. *)

val check_numeric_expr :
  scope:string ->
  tu_env ->
  Ast.expr Ast.node ->
  string ->
  Check_env.diagnostic list
(** [check_numeric_expr ~scope env e what] checks that [e] evaluates to a
    numeric value. [what] describes the context for error messages. *)

val check_nonneg_id :
  scope:string ->
  tu_env ->
  Ast.expr Ast.node ->
  string ->
  Check_env.diagnostic list
(** [check_nonneg_id ~scope env e what] checks that [e] evaluates to a
    non-negative integer. *)

val check_array_expr :
  scope:string -> tu_env -> Ast.expr Ast.node -> Check_env.diagnostic list
(** [check_array_expr ~scope env e] validates an array/struct literal
    expression. *)

val check_struct_expr_dupes :
  scope:string -> Ast.expr Ast.node -> Check_env.diagnostic list
(** [check_struct_expr_dupes ~scope e] checks for duplicate member names in a
    struct expression. *)

(** {1:helpers Type helpers} *)

val is_numeric_type : Ast.type_name -> bool
(** [is_numeric_type tn] is [true] if [tn] is a primitive numeric type. *)

val is_numeric_resolved_tu : tu_env -> Ast.type_name Ast.node -> bool
(** [is_numeric_resolved_tu env tn] is [true] if [tn] resolves to a numeric type
    in the TU environment. *)

val is_integer_type : Ast.type_name -> bool
(** [is_integer_type tn] is [true] if [tn] is an integer type. *)

val is_integer_type_resolved : tu_env -> Ast.type_name Ast.node -> bool
(** [is_integer_type_resolved env tn] is [true] if [tn] resolves to an integer
    type, following type aliases. *)

val count_format_repls : string -> int
(** [count_format_repls s] counts the number of ['{}'] placeholders in [s]. *)

val check_format_string :
  scope:string -> Ast.loc -> string -> int -> Check_env.diagnostic list
(** [check_format_string ~scope loc fmt n] validates a format string [fmt]
    expecting [n] replacements. *)

(** {1:lookup Component lookup} *)

val component : tu_env -> Ast.qual_ident Ast.node -> Ast.def_component option
(** [component env qi] resolves a component reference, walking through module
    scopes if necessary. *)

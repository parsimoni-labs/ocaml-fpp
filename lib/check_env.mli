(** Shared types and utilities for state machine checks.

    This module provides the common types, environment construction, and AST
    helpers used by both {!Check_core} (error-level checks) and {!Check_warn}
    (warning-level analyses). It is internal to the [fpp] library. *)

(** {1:maps Ordered maps and sets over strings} *)

module SMap : Map.S with type key = string
module SSet : Set.S with type elt = string

(** {1:diagnostics Diagnostics}

    A diagnostic carries a severity, a source location, the name of the
    enclosing state machine, and a human-readable message. Errors indicate
    semantic violations that must be fixed; warnings indicate suspicious
    patterns that may be intentional. *)

type diagnostic = {
  severity : [ `Error | `Warning ];
  loc : Ast.loc;
  sm_name : string;
  msg : string;
}

val pp_diagnostic : diagnostic Fmt.t
(** Formats a diagnostic as [file:line:col: severity in SM 'name': message]. *)

val error : sm_name:string -> Ast.loc -> string -> diagnostic
(** [error ~sm_name loc msg] is an error diagnostic. *)

val errorf :
  sm_name:string ->
  Ast.loc ->
  ('a, Format.formatter, unit, diagnostic) format4 ->
  'a
(** [errorf ~sm_name loc fmt] is [error ~sm_name loc (Fmt.str fmt ...)]. *)

val warning : sm_name:string -> Ast.loc -> string -> diagnostic
(** [warning ~sm_name loc msg] is a warning diagnostic. *)

val warningf :
  sm_name:string ->
  Ast.loc ->
  ('a, Format.formatter, unit, diagnostic) format4 ->
  'a
(** [warningf ~sm_name loc fmt] is [warning ~sm_name loc (Fmt.str fmt ...)]. *)

(** {1:env Name environment}

    The environment maps each declared name (action, guard, signal, state,
    choice, type, constant) to its source location. It also records optional
    type annotations on actions, guards, and signals for typed element checking,
    and type alias definitions for format validation. *)

type env = {
  actions : Ast.loc SMap.t;
  guards : Ast.loc SMap.t;
  signals : Ast.loc SMap.t;
  states : Ast.loc SMap.t;
  choices : Ast.loc SMap.t;
  types : Ast.loc SMap.t;
  constants : Ast.loc SMap.t;
  action_types : Ast.type_name Ast.node option SMap.t;
  guard_types : Ast.type_name Ast.node option SMap.t;
  signal_types : Ast.type_name Ast.node option SMap.t;
  type_aliases : Ast.type_name Ast.node SMap.t;
}

val build_sm_env : Ast.state_machine_member Ast.node Ast.annotated list -> env
(** [build_sm_env members] collects all top-level declarations in a state
    machine body into a name environment. *)

val build_state_env : Ast.def_state -> env -> env
(** [build_state_env state parent_env] extends [parent_env] with the states and
    choices defined directly inside [state]. *)

(** {1:targets Transition target helpers} *)

val target_name : Ast.qual_ident Ast.node -> string
(** [target_name qi] extracts the simple or qualified name from a transition
    target. *)

val is_qualified_target : Ast.qual_ident Ast.node -> bool
(** [is_qualified_target qi] is [true] when [qi] is a dotted path. *)

val build_choice_map :
  Ast.state_machine_member Ast.node Ast.annotated list ->
  (string, Ast.def_choice) Hashtbl.t
(** [build_choice_map members] collects all choice definitions (including those
    nested inside states) into a hashtable keyed by choice name. Used by scope
    validation and liveness analysis. *)

(** {1:state_introspection State introspection} *)

val state_direct_signals : Ast.def_state -> SSet.t
(** [state_direct_signals st] returns the set of signal names handled directly
    by [st] (via [on signal ...] transitions). *)

val state_has_substates : Ast.def_state -> bool
(** [state_has_substates st] is [true] when [st] contains nested state
    definitions. *)

val collect_substates : Ast.def_state -> Ast.def_state list
(** [collect_substates st] returns the immediate child states of [st]. *)

val collect_sm_states :
  Ast.state_machine_member Ast.node Ast.annotated list -> Ast.def_state list
(** [collect_sm_states members] returns the top-level states of a state machine
    body. *)

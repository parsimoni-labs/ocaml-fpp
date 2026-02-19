(** Core error-level checks for state machines.

    These checks detect semantic errors that must be fixed before code
    generation. They always run regardless of the analysis configuration.

    {b Name resolution.} Duplicate declarations (actions, guards, signals,
    states, choices, constants, types) and undefined references -- with
    contextual hints when a name exists in a different namespace (e.g. using a
    guard name where an action is expected).

    {b Structural validation.} Missing or duplicate initial transitions (at both
    SM and nested-state level), duplicate signal handlers in a single state,
    unreachable states and choices, and choice cycles.

    {b Scope validation.} Initial transitions must target states or choices
    defined in the same scope -- they may not reach across nesting boundaries.

    {b Type safety.} Undefined type and constant references, invalid default
    values, format specifiers on non-numeric types, and mismatched typed actions
    and guards in transition contexts.

    This module is internal to the [fpp] library. *)

val run :
  sm_name:string ->
  sm_loc:Ast.loc ->
  Check_env.env ->
  Ast.state_machine_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~sm_name ~sm_loc env members] runs all core checks on the state machine
    body [members] within the name environment [env]. Returns a list of error
    diagnostics, ordered by check category. *)

val is_builtin_type : string -> bool
(** [is_builtin_type name] is [true] if [name] is a built-in FPP type. *)

val expr_ident_refs : Ast.expr Ast.node -> Ast.ident Ast.node list
(** [expr_ident_refs e] collects all identifier references in expression [e]. *)

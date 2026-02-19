(** Component instance and topology validation.

    Validates component instances (property requirements by component kind),
    instance ID conflicts, and topology members (imports, connection patterns,
    instance references). This module is internal to the [fpp] library. *)

val run :
  scope:string ->
  Check_tu_env.tu_env ->
  Ast.module_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~scope env members] validates all component instances and topologies
    within [members]. *)

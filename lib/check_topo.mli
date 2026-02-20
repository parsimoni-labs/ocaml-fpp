(** Component instance and topology validation.

    Validates component instances (property requirements by component kind),
    instance ID conflicts, and topology members (imports, connection patterns,
    instance references). This module is internal to the [fpp] library. *)

val run :
  scope:string ->
  unconnected:Check_env.level ->
  sync_cycle:Check_env.level ->
  Check_tu_env.tu_env ->
  Ast.module_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~scope ~unconnected ~sync_cycle env members] validates all component
    instances and topologies within [members]. The [unconnected] and
    [sync_cycle] parameters control the severity of the corresponding
    warning-level analyses. *)

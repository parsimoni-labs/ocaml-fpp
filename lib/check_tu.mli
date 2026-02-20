(** Translation-unit-level semantic checks.

    Runs checks across the full translation unit: redefinitions, symbol kind
    validation, dependency cycles, expression evaluation, component member
    validation, and instance/topology checks. This module is internal to the
    [fpp] library. *)

val run :
  unconnected:Check_env.level ->
  sync_cycle:Check_env.level ->
  Ast.module_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~unconnected ~sync_cycle members] runs all TU-level checks on the
    translation unit [members]. The [unconnected] and [sync_cycle] parameters
    control the severity of the corresponding topology warning analyses. Returns
    a list of diagnostics. *)

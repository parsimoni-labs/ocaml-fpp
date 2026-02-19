(** Component member validation.

    Validates all aspects of component definitions: port requirements, member
    IDs, duplicate detection, type references, and special port constraints.
    Also validates port definitions and interface definitions. This module is
    internal to the [fpp] library. *)

val run :
  scope:string ->
  Check_tu_env.tu_env ->
  Ast.module_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~scope env members] validates all component, port, and interface
    definitions within [members]. *)

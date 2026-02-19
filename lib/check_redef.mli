(** Redefinition detection for TU-level definitions.

    Detects duplicate declarations at each scope level: modules, components,
    enums, structs. This module is internal to the [fpp] library. *)

val run :
  scope:string ->
  Ast.module_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~scope members] checks for duplicate definitions at every scope level
    within [members]. *)

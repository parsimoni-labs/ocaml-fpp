(** Symbol kind validation and dependency cycle detection.

    Checks that referenced symbols have the expected kind (type, constant,
    component, etc.) and detects definition cycles. This module is internal to
    the [fpp] library. *)

val run :
  scope:string ->
  Check_tu_env.tu_env ->
  Ast.module_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~scope env members] checks symbol kind validity and dependency cycles
    within [members]. *)

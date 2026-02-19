(** Type and constant definition validation.

    Validates array, enum, struct, constant, and type alias definitions at the
    TU level: size constraints, format specifiers, undefined references,
    expression evaluation, and spec_loc paths. This module is internal to the
    [fpp] library. *)

val run :
  scope:string ->
  Check_tu_env.tu_env ->
  Ast.module_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
(** [run ~scope env members] validates all type and constant definitions within
    [members]. *)

val is_type_displayable :
  Ast.module_member Ast.node Ast.annotated list -> Ast.type_name -> bool
(** [is_type_displayable members tn] is [true] if [tn] is a displayable type.
    Abstract types are not displayable. *)

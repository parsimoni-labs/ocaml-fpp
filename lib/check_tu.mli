(** Translation-unit-level semantic checks.

    Runs checks across the full translation unit: redefinitions, symbol kind
    validation, dependency cycles, expression evaluation, component member
    validation, and instance/topology checks. This module is internal to the
    [fpp] library. *)

val run :
  Ast.module_member Ast.node Ast.annotated list -> Check_env.diagnostic list
(** [run members] runs all TU-level checks on the translation unit [members].
    Returns a list of error diagnostics. *)

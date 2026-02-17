(** State machine static analysis.

    Runs semantic checks on FPP state machines and reports diagnostics. *)

type diagnostic = {
  severity : [ `Error | `Warning ];
  loc : Ast.loc;
  sm_name : string;
  msg : string;
}

val pp_diagnostic : diagnostic Fmt.t
(** [pp_diagnostic] is a pretty-printer for diagnostics. *)

val state_machine : Ast.def_state_machine -> diagnostic list
(** Run all checks on one state machine. *)

val run : Ast.translation_unit -> diagnostic list
(** Run all checks on every state machine in the translation unit. *)

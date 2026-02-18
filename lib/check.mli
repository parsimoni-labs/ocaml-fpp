(** State machine static analysis.

    Runs semantic checks on FPP state machines and reports diagnostics. *)

(** {1 Analysis categories} *)

type analysis =
  | Coverage
  | Liveness
      (** Optional analyses that can be disabled. Core checks (name
          redefinition, initial transitions, undefined references, reachability,
          choice cycles, type checking) always run. *)

val all_analyses : analysis list
(** All optional analyses. *)

val analysis_of_string : string -> analysis option
(** Parse an analysis name. *)

val analyses : string list
(** Names of all optional analyses, for CLI documentation. *)

(** {1 Configuration} *)

type config
(** Analysis configuration. *)

val default : config
(** Default configuration: all analyses enabled. *)

val skip : analysis list -> config -> config
(** [skip analyses config] disables the given analyses. *)

(** {1 Diagnostics} *)

type diagnostic = {
  severity : [ `Error | `Warning ];
  loc : Ast.loc;
  sm_name : string;
  msg : string;
}

val pp_diagnostic : diagnostic Fmt.t
(** Pretty-printer for diagnostics. *)

(** {1 Running checks} *)

val state_machine : config -> Ast.def_state_machine -> diagnostic list
(** Run checks on one state machine. *)

val run : config -> Ast.translation_unit -> diagnostic list
(** Run checks on every state machine in the translation unit. *)

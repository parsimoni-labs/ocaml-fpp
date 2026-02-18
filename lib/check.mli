(** State machine static analysis.

    Runs semantic checks on FPP state machines and reports diagnostics. Checks
    are split into two categories:

    - {b Core checks} always run and detect semantic errors that must be fixed:
      name redefinition, missing or duplicate initial transitions, undefined
      references, unreachable states, choice cycles, scope violations, and type
      mismatches. See {!Check_core} for details.

    - {b Warning-level analyses} are optional and detect suspicious patterns:
      missing signal handlers, livelock cycles, unused declarations, transition
      shadowing, and potential deadlocks. See {!Check_warn} for details. Each
      analysis can be individually disabled via {!skip}. *)

(** {1 Analysis categories} *)

type analysis =
  | Coverage
      (** Signal coverage: warns when a leaf state has no handler for a declared
          signal (directly or inherited from an ancestor). *)
  | Liveness
      (** Liveness: warns when a group of states forms a cycle with no exit path
          to a terminal state. *)
  | Unused
      (** Unused declarations: warns when an action, guard, or signal is
          declared but never referenced. *)
  | Shadowing
      (** Transition shadowing: warns when a child state handles a signal that
          an ancestor already handles, overriding the parent's handler. *)
  | Deadlock
      (** Deadlock detection: warns when a leaf state has no outgoing
          transitions and no ancestor provides a handler. *)

val all_analyses : analysis list
(** All optional analyses. *)

val analysis_of_string : string -> analysis option
(** [analysis_of_string s] parses an analysis name. Returns [None] for
    unrecognised names. *)

val analyses : string list
(** Names of all optional analyses, for CLI documentation. *)

(** {1 Configuration} *)

type config
(** Analysis configuration controlling which optional analyses run. *)

val default : config
(** Default configuration: all analyses enabled. *)

val skip : analysis list -> config -> config
(** [skip analyses config] returns a new configuration with the given analyses
    disabled. Core checks are unaffected. *)

(** {1 Diagnostics} *)

type diagnostic = {
  severity : [ `Error | `Warning ];
  loc : Ast.loc;
  sm_name : string;
  msg : string;
}
(** A diagnostic message produced by the analysis. Errors indicate semantic
    violations; warnings indicate suspicious patterns. *)

val pp_diagnostic : diagnostic Fmt.t
(** Formats a diagnostic as [file:line:col: severity in SM 'name': message]. *)

(** {1 Running checks} *)

val state_machine : config -> Ast.def_state_machine -> diagnostic list
(** [state_machine config sm] runs all enabled checks on a single state machine
    definition. Returns errors followed by warnings. External state machines (no
    body) produce no diagnostics. *)

val run : config -> Ast.translation_unit -> diagnostic list
(** [run config tu] runs checks on every state machine in [tu], including those
    nested inside modules. *)

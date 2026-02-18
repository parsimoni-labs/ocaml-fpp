(** State machine to D2 rendering.

    Produces D2 diagrams from FPP state machine definitions. D2 is a modern
    diagramming language ({{:https://d2lang.com}d2lang.com}) with clean default
    styling and native support for hierarchical containers.

    The output can be piped to [d2 - output.svg] for visualisation. External
    state machines (no body) produce no output. *)

val pp : Ast.def_state_machine Fmt.t
(** Pretty-prints a state machine definition as a D2 diagram. External state
    machines (no body) produce no output. *)

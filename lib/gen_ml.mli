(** State machine to OCaml code generation.

    Produces idiomatic OCaml modules from FPP state machine definitions using
    GADTs for typed signals, module types for actions and guards, and functors
    for dependency injection.

    External state machines (no body) produce no output. *)

val pp : Ast.def_state_machine Fmt.t
(** Pretty-prints a state machine definition as an OCaml module. External state
    machines (no body) produce no output. *)

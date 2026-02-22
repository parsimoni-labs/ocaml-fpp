(** FPP to OCaml code generation.

    Produces idiomatic OCaml modules from FPP state machine definitions and
    topology definitions. State machines use GADTs for typed signals, module
    types for actions and guards, and functors for dependency injection.
    Topologies become OCaml functors with typed wiring.

    External state machines (no body) produce no output. *)

val pp : Ast.def_state_machine Fmt.t
(** Pretty-prints a state machine definition as an OCaml module. External state
    machines (no body) produce no output. *)

val pp_topology : Ast.translation_unit -> Ast.def_topology Fmt.t
(** [pp_topology tu] is a pretty-printer for topology [topo] as an OCaml module.
    Generates module type signatures for each component and a [Make] functor
    that wires connections. *)

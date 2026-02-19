(** State machine to Graphviz DOT rendering.

    Produces DOT digraphs from FPP state machine definitions. Graphviz DOT gives
    first-class edge labels, self-loop support, [subgraph cluster_*] containers,
    and HTML table labels for structured state annotations.

    The output can be piped to [dot -Tsvg -o output.svg] for visualisation.
    External state machines (no body) produce no output. *)

val pp : Ast.def_state_machine Fmt.t
(** Pretty-prints a state machine definition as a Graphviz DOT digraph. External
    state machines (no body) produce no output. *)

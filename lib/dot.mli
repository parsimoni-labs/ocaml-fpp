(** Graphviz DOT rendering for state machines and topologies.

    Produces DOT digraphs from FPP state machine definitions and topology
    definitions. State machines render as state/transition diagrams; topologies
    render as component wiring graphs with import clusters.

    The output can be piped to [dot -Tsvg -o output.svg] for visualisation.
    External state machines (no body) produce no output. *)

val pp : Ast.def_state_machine Fmt.t
(** Pretty-prints a state machine definition as a Graphviz DOT digraph. External
    state machines (no body) produce no output. *)

val pp_topology : Ast.translation_unit -> Ast.def_topology Fmt.t
(** Pretty-prints a topology as a Graphviz DOT digraph. Component instances are
    nodes; connections are directed edges. Imported sub-topologies are rendered
    as cluster subgraphs. *)

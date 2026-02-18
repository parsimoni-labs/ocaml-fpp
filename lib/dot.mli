(** State machine to Graphviz DOT rendering.

    Produces DOT digraphs from FPP state machine definitions. Hierarchical
    states become cluster subgraphs (boxed groups), choices become diamond
    nodes, and signal transitions become labelled edges. Initial transitions are
    shown as dashed edges from synthetic start points.

    The output can be piped directly to [dot -Tpng] or [dot -Tsvg] for
    visualisation. External state machines (no body) produce no output. *)

val pp : Ast.def_state_machine Fmt.t
(** [pp ppf sm] writes a DOT digraph for state machine [sm] to [ppf]. *)

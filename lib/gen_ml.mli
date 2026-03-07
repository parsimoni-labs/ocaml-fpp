(** FPP to OCaml code generation.

    Produces idiomatic OCaml modules from FPP state machine definitions and
    topology definitions. State machines use GADTs for typed signals, module
    types for actions and guards, and functors for dependency injection.
    Topologies produce module aliases, functor applications, and lazy group
    bindings.

    External state machines (no body) produce no output. *)

val pp : Ast.def_state_machine Fmt.t
(** Pretty-prints a state machine definition as an OCaml module. External state
    machines (no body) produce no output. *)

val pp_topology : Ast.translation_unit -> Ast.def_topology Fmt.t
(** [pp_topology tu] pretty-prints a topology as OCaml code. Empty topologies
    produce no output. *)

val topology_has_output : Ast.translation_unit -> Ast.def_topology -> bool
(** [topology_has_output tu topo] is [true] when [topo] would produce OCaml
    code. Returns [false] for empty topologies (no instances). *)

val topology_is_fully_bound : Ast.translation_unit -> Ast.def_topology -> bool
(** [topology_is_fully_bound tu topo] is [true] when [topo] has non-runtime
    instances. *)

val topology_connect_names :
  Ast.translation_unit -> Ast.def_topology -> string list
(** [topology_connect_names tu topo] returns the connection group names for
    [topo] (already lowercased by {!collect_direct_connections}). *)

val pp_main_entry_multi : Format.formatter -> (string * string) list -> unit
(** [pp_main_entry_multi ppf topos] emits a [let () = Lwt_main.run (...)] entry
    point. Each element is [(topo_module_name, lazy_name)] where [lazy_name] is
    a lazy group binding name. *)

val topology_active_instance_names :
  Ast.translation_unit -> Ast.def_topology -> (string * string) list
(** [topology_active_instance_names tu topo] returns [(lazy_name, lazy_name)]
    pairs for lazy group bindings in [topo]. Used by [pp_entry_point] to force
    the last group binding. *)

val pp_entry_point :
  Format.formatter -> topo_name:string -> (string * string) list -> unit
(** [pp_entry_point ppf ~topo_name names] emits a Mirage_runtime-based entry
    point that registers cmdliner arguments, parses [Mirage_bootvar.argv],
    initialises RNG and logging, forces the last lazy group binding, and runs
    via [Unix_os.Main.run]. *)

val pp_topology_module_types : Ast.translation_unit -> Ast.def_topology Fmt.t
(** [pp_topology_module_types tu ppf topo] emits [module type X = sig ... end]
    declarations for components that have typed interface ports. Used alongside
    [pp_topology] when a [.mli] is also generated, so OCaml checks the derived
    signature against the named [@ ocaml.sig] constraint. *)

(** {2 .mli Generation} *)

val pp_topology_mli : Ast.translation_unit -> Ast.def_topology Fmt.t
(** [pp_topology_mli tu] pretty-prints the interface of a topology. Emits module
    declarations for all non-runtime instances and [val] declarations for each
    connection group lazy binding. Instances with [@ ocaml.sig] get the named
    module type; non-leaf instances without it get [sig type t end]; leaf
    instances with qualified component paths get module aliases. *)

(** {2 Topology Helpers} *)

val collect_topologies : Ast.translation_unit -> Ast.def_topology list
(** [collect_topologies tu] collects all topology definitions from [tu],
    including those nested in modules. *)

val flatten_topology :
  Ast.translation_unit -> Ast.def_topology -> Ast.def_topology
(** [flatten_topology tu topo] resolves [import] directives recursively. Public
    instances and connections from imported topologies are merged into the
    result. *)

val resolve_topology_instances :
  Ast.translation_unit ->
  Ast.def_topology ->
  (string * Ast.def_component_instance * Ast.def_component) list
(** [resolve_topology_instances tu topo] is the list of
    [(instance_name, component_instance, component)] triples for all component
    instances in [topo]. *)

val collect_direct_connections :
  Ast.def_topology -> (string * Ast.connection list) list
(** [collect_direct_connections topo] is the direct connections in [topo],
    grouped by graph name. Groups with the same name are merged. *)

val all_connections : (string * Ast.connection list) list -> Ast.connection list
(** [all_connections groups] merges all connection groups into a single list. *)

val pid_inst_name : Ast.port_instance_id -> string
(** [pid_inst_name pid] extracts the instance name from a port instance
    identifier. *)

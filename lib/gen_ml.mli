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
    Generates component module type signatures and a [Make] functor that wires
    connections via direct functor application. Follows the device-centric
    MirageOS functor pattern: functor parameters are target component module
    types (not per-port adapters). Components that are both functor targets and
    have outputs get an [_S] operations-only module type. Active components use
    [Lwt.t] return types.

    In annotated (functor-application) mode, passive components are module-only:
    they get functor applications but no record fields, connect calls, or Make
    parameters. Import-only topologies (all instances passive) produce no
    output. *)

val topology_has_output : Ast.translation_unit -> Ast.def_topology -> bool
(** [topology_has_output tu topo] is [true] when [topo] would produce OCaml
    code. Returns [false] for import-only topologies where every instance is
    passive. *)

val topology_is_fully_bound : Ast.translation_unit -> Ast.def_topology -> bool
(** [topology_is_fully_bound tu topo] is [true] when every leaf instance in
    [topo] is bound via [@ ocaml.module]. A fully-bound topology has no functor
    parameters and its [Make.connect] can be called with [()]. *)

val pp_module_types :
  Ast.translation_unit -> Ast.def_topology list -> Format.formatter -> unit
(** [pp_module_types tu topos ppf] emits port-based module types for leaf
    components in [topos], preceded by a comment header. *)

val has_module_types : Ast.translation_unit -> Ast.def_topology list -> bool
(** [has_module_types tu topos] is [true] if [topos] have leaf component module
    types to emit. *)

val topology_connect_names :
  Ast.translation_unit -> Ast.def_topology -> string list
(** [topology_connect_names tu topo] returns the connection group names for
    [topo] (already lowercased by {!collect_direct_connections}). *)

val pp_main_entry_multi : Format.formatter -> (string * string) list -> unit
(** [pp_main_entry_multi ppf topos] emits a [let () = Lwt_main.run (...)] entry
    point. Each element is [(topo_module_name, func_name)] where [func_name] is
    a connection group name. *)

val topology_active_instance_names :
  Ast.translation_unit -> Ast.def_topology -> (string * string) list
(** [topology_active_instance_names tu topo] returns [(var_name, module_name)]
    pairs for active (non-passive) instances in [topo], in topo-sorted order.
    These are the instances that receive lazy bindings in fully-bound mode. *)

val topology_start_info :
  Ast.translation_unit -> Ast.def_topology -> (string * string list) option
(** [topology_start_info tu topo] returns [Some (module_name, var_names)] when
    the last active instance in [topo] is a non-leaf (has dependencies),
    indicating it should receive a [.start] call. Returns [None] when all active
    instances are leaves. *)

val pp_flat_entry_point :
  Format.formatter ->
  (string * string) list ->
  start:(string * string list) option ->
  unit
(** [pp_flat_entry_point ppf names ~start] emits a [let () = Lwt_main.run (...)]
    entry point that forces each lazy binding. When [~start] is
    [Some (mod_name, args)], emits [Mod_name.start arg1 ...]; otherwise emits
    [Lwt.return ()]. Each element of [names] is [(var_name, module_name)]. *)

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
(** [all_connections groups] merges all connection groups into a flat list. *)

val pid_inst_name : Ast.port_instance_id -> string
(** [pid_inst_name pid] extracts the instance name from a port instance
    identifier. *)

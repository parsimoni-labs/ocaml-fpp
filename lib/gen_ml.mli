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

val pp_module_types :
  Ast.translation_unit -> Ast.def_topology list -> Format.formatter -> unit
(** [pp_module_types tu topos ppf] emits module type aliases for leaf components
    in [topos]. Components annotated with [@ ocaml.sig] produce aliases (e.g.
    [module type NET = Mirage_net.S]); others get port-based module types. *)

val topology_annotations :
  Ast.translation_unit -> Ast.def_topology -> string list
(** [topology_annotations tu topo] extracts pre-annotations from the topology
    definition wrapper (e.g. [@ ocaml.main]). *)

val parse_main_annotation : string list -> string option option
(** [parse_main_annotation annots] extracts [@ ocaml.main] from an annotation
    list. Returns [Some (Some fn)] for [@ ocaml.main fn], [Some None] for bare
    [@ ocaml.main], or [None] if not present. *)

val pp_main_entry :
  Format.formatter -> wrap:bool -> string -> string option -> unit
(** [pp_main_entry ppf ~wrap topo_name start_fn] emits
    [let () = Lwt_main.run (...)] using the topology's [Make.connect]. When
    [start_fn] is [Some fn], the connect result is passed to [fn]. *)

val pp_main_entry_multi :
  Format.formatter -> prefix:string -> (string * string option) list -> unit
(** [pp_main_entry_multi ppf ~prefix topos] emits a combined entry point. Each
    element is [(topo_name, start_fn_opt)]. The [prefix] is the OCaml module
    containing the topology definitions (inferred from filename). *)

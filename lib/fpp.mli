(** FPP Parser.

    This module parses {{:https://nasa.github.io/fpp/fpp-users-guide.html}FPP}
    (F Prime Prime) source files into an abstract syntax tree. FPP is the
    modeling language for NASA's F Prime flight software framework.

    The parser is implemented using Menhir and supports the full FPP grammar
    including components, topologies, ports, commands, events, telemetry,
    parameters, data products, and state machines.

    {2 Example}

    {[
      let tu = Fpp.parse_file "Led.fpp" in
      let comp = Fpp.component tu in
      Printf.printf "Component: %s\n" (Ast.unnode comp.comp_name)
    ]} *)

module Ast = Ast
module Check = Check
module Dot = Dot
module Fpv = Fpv
module Gen_ml = Gen_ml

(** {1 Parse Errors} *)

type error = { msg : string; file : string; line : int; col : int }

exception Parse_error of error
exception Lexer_error of string * Lexing.position

val pp_error : error Fmt.t
(** [pp_error] is a pretty-printer for parse errors. *)

(** {1 Parsing} *)

val parse_string : ?filename:string -> string -> Ast.translation_unit
(** [parse_string ?filename content] parses FPP content from a string.
    @raise Parse_error on syntax errors. *)

val parse_file : string -> Ast.translation_unit
(** [parse_file filename] parses an FPP file.
    @raise Parse_error on syntax errors. *)

(** {1 AST Queries} *)

val modules : Ast.translation_unit -> Ast.def_module list
(** [modules tu] is all module definitions in [tu]. *)

val components : Ast.translation_unit -> Ast.def_component list
(** [components tu] is all component definitions in [tu]. *)

val components_with_namespace :
  Ast.translation_unit -> (string list * Ast.def_component) list
(** [components_with_namespace tu] is all components with their parent module
    path. Returns [(ns, comp)] pairs where [ns] is the list of parent module
    names. *)

val component_namespace : Ast.translation_unit -> Ast.def_component -> string
(** [component_namespace tu comp] is the C++ namespace for component [comp],
    i.e., the "::" separated parent module path. Returns "" if at top level. *)

val require_components : Ast.translation_unit -> Ast.def_component list
(** [require_components tu] is all components in [tu], raising [Parse_error] if
    none. *)

val component : ?name:string -> Ast.translation_unit -> Ast.def_component
(** [component ?name tu] is the component named [name] in [tu], or the only one.
    @param name
      Component name to find. If omitted and exactly one component exists, that
      component is used.
    @raise Parse_error
      if no components found, name not found, or multiple components exist
      without a name specified. *)

val topologies : Ast.translation_unit -> Ast.def_topology list
(** [topologies tu] is all topology definitions in [tu]. *)

val instances : Ast.translation_unit -> Ast.def_component_instance list
(** [instances tu] is all component instance definitions in [tu]. *)

val port_defs : Ast.translation_unit -> Ast.def_port list
(** [port_defs tu] is all port definitions in [tu]. *)

val enums : Ast.translation_unit -> Ast.def_enum list
(** [enums tu] is all enum definitions in [tu]. *)

val structs : Ast.translation_unit -> Ast.def_struct list
(** [structs tu] is all struct definitions in [tu]. *)

val constants : Ast.translation_unit -> Ast.def_constant list
(** [constants tu] is all constant definitions in [tu]. *)

val state_machines : Ast.translation_unit -> Ast.def_state_machine list
(** [state_machines tu] is all state machine definitions in [tu]. *)

(** {1 AST Helpers} *)

val type_to_string : Ast.type_name -> string
(** [type_to_string t] is the string representation of FPP type [t]. *)

val expr_to_int : Ast.expr -> int option
(** [expr_to_int e] is the integer value of literal expression [e], if any. *)

val expr_to_string : Ast.expr -> string
(** [expr_to_string e] is the string representation of expression [e]. *)

val qual_ident_to_string : Ast.qual_ident -> string
(** [qual_ident_to_string q] is qualified identifier [q] as a dotted string. *)

(** {1 Component Member Extractors} *)

val commands : Ast.def_component -> Ast.spec_command list
(** [commands comp] is all command definitions in component [comp]. *)

val ports : Ast.def_component -> Ast.port_instance_general list
(** [ports comp] is all general port instances in component [comp]. *)

val events : Ast.def_component -> Ast.spec_event list
(** [events comp] is all event definitions in component [comp]. *)

val telemetry : Ast.def_component -> Ast.spec_tlm_channel list
(** [telemetry comp] is all telemetry channel definitions in component [comp].
*)

val params : Ast.def_component -> Ast.spec_param list
(** [params comp] is all parameter definitions in component [comp]. *)

val is_input : Ast.general_port_kind -> bool
(** [is_input kind] is [true] if [kind] is an input port. *)

val is_output : Ast.general_port_kind -> bool
(** [is_output kind] is [true] if [kind] is an output port. *)

val component_enums : Ast.def_component -> Ast.def_enum list
(** [component_enums comp] is enums defined within component [comp]. *)

val enums_with_namespace :
  Ast.translation_unit -> (string list * Ast.def_enum) list
(** [enums_with_namespace tu] is all enums with their parent module/component
    namespace path. *)

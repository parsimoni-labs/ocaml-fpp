(** FPP Parser - Full FPP language parser using Menhir.

    This module provides the main entry point for parsing FPP files using the
    menhir-generated parser. *)

module Ast = Ast

(** {1 Parse Errors} *)

type error = { msg : string; file : string; line : int; col : int }

exception Parse_error of error

let pp_error ppf e = Fmt.pf ppf "%s:%d:%d: %s" e.file e.line e.col e.msg

(** {1 Parsing} *)

exception Lexer_error = Lexer.Error

(* Tokens that can end an expression (value-ending tokens). *)
let is_value_end = function
  | Parser.INT _ | Parser.FLOAT _ | Parser.STRING _ | Parser.BOOL _
  | Parser.IDENT _ | Parser.PRIM_TYPE _ | Parser.RPAREN | Parser.RBRACKET
  | Parser.RBRACE ->
      true
  (* Contextual keywords usable as identifiers *)
  | Parser.ENTRY | Parser.EXIT | Parser.STATE | Parser.ACTION | Parser.GUARD
  | Parser.SIGNAL | Parser.MACHINE | Parser.PHASE | Parser.FORMAT | Parser.ID
  | Parser.SIZE | Parser.TIME | Parser.ON | Parser.CHANGE | Parser.HIGH
  | Parser.LOW | Parser.RED | Parser.ORANGE | Parser.YELLOW | Parser.ALWAYS
  | Parser.BLOCK | Parser.DROP | Parser.HOOK | Parser.BASE | Parser.CPU
  | Parser.STACK | Parser.QUEUE | Parser.GROUP | Parser.TEXT | Parser.GET
  | Parser.SET | Parser.SEND | Parser.RECV | Parser.RESP | Parser.REG
  | Parser.SAVE | Parser.SECONDS ->
      true
  | _ -> false

(* Tokens that can start an expression (value-starting tokens). *)
let is_value_start = function
  | Parser.INT _ | Parser.FLOAT _ | Parser.STRING _ | Parser.BOOL _
  | Parser.IDENT _ | Parser.PRIM_TYPE _ | Parser.LPAREN | Parser.LBRACKET
  | Parser.LBRACE | Parser.MINUS ->
      true
  | Parser.ENTRY | Parser.EXIT | Parser.STATE | Parser.ACTION | Parser.GUARD
  | Parser.SIGNAL | Parser.MACHINE | Parser.PHASE | Parser.FORMAT | Parser.ID
  | Parser.SIZE | Parser.TIME | Parser.ON | Parser.CHANGE | Parser.HIGH
  | Parser.LOW | Parser.RED | Parser.ORANGE | Parser.YELLOW | Parser.ALWAYS
  | Parser.BLOCK | Parser.DROP | Parser.HOOK | Parser.BASE | Parser.CPU
  | Parser.STACK | Parser.QUEUE | Parser.GROUP | Parser.TEXT | Parser.GET
  | Parser.SET | Parser.SEND | Parser.RECV | Parser.RESP | Parser.REG
  | Parser.SAVE | Parser.SECONDS ->
      true
  | _ -> false

(* Wrap the lexer to insert virtual commas for newline-separated elements
   inside [...] brackets (array literals). When a newline is crossed between
   a value-ending and a value-starting token inside brackets, emit a COMMA. *)
let newline_aware_lexer base_lexer =
  let bracket_depth = ref 0 in
  let last_token = ref Parser.EOF in
  let pending = Queue.create () in
  Lexer.reset ();
  fun lexbuf ->
    if not (Queue.is_empty pending) then begin
      let tok = Queue.pop pending in
      last_token := tok;
      tok
    end
    else begin
      let tok = base_lexer lexbuf in
      let nl = Lexer.saw_newline () in
      if
        !bracket_depth > 0 && nl && is_value_end !last_token
        && is_value_start tok
      then begin
        Queue.push tok pending;
        last_token := Parser.COMMA;
        Parser.COMMA
      end
      else begin
        (match tok with
        | Parser.LBRACKET -> incr bracket_depth
        | Parser.RBRACKET -> if !bracket_depth > 0 then decr bracket_depth
        | _ -> ());
        last_token := tok;
        tok
      end
    end

let parse_lexbuf lexbuf =
  try Parser.translation_unit (newline_aware_lexer Lexer.token) lexbuf with
  | Lexer.Error (msg, pos) ->
      raise
        (Parse_error
           {
             msg;
             file = pos.Lexing.pos_fname;
             line = pos.Lexing.pos_lnum;
             col = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
           })
  | Parser.Error ->
      let pos = lexbuf.Lexing.lex_curr_p in
      raise
        (Parse_error
           {
             msg = "syntax error";
             file = pos.Lexing.pos_fname;
             line = pos.Lexing.pos_lnum;
             col = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
           })

let parse_string ?(filename = "<string>") content =
  let lexbuf = Lexing.from_string content in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  parse_lexbuf lexbuf

let parse_file filename =
  let ic = open_in filename in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let lexbuf = Lexing.from_channel ic in
      lexbuf.Lexing.lex_curr_p <-
        { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
      parse_lexbuf lexbuf)

(** {1 AST Queries} *)

(* Helper to extract data from annotated nodes *)
let unannotate_node (_, node, _) = node.Ast.data

let modules tu =
  List.filter_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_module m -> Some m
      | _ -> None)
    tu.Ast.tu_members

let rec collect_components members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_component c -> [ c ]
      | Ast.Mod_def_module m -> collect_components m.Ast.module_members
      | _ -> [])
    members

let components tu = collect_components tu.Ast.tu_members

(** Collect components with their parent module namespace (for C++
    qualification) *)
let rec collect_components_with_ns ?(ns = []) members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_component c -> [ (ns, c) ]
      | Ast.Mod_def_module m ->
          let new_ns = ns @ [ m.Ast.module_name.data ] in
          collect_components_with_ns ~ns:new_ns m.Ast.module_members
      | _ -> [])
    members

let components_with_namespace tu = collect_components_with_ns tu.Ast.tu_members

(** Get the C++ namespace string for a component ("::" separated) *)
let component_namespace tu comp =
  let pairs = components_with_namespace tu in
  match
    List.find_opt
      (fun (_, c) -> c.Ast.comp_name.data = comp.Ast.comp_name.data)
      pairs
  with
  | Some (ns, _) -> String.concat "::" ns
  | None -> ""

(** Get components with a helpful error if none found. *)
let require_components tu =
  match collect_components tu.Ast.tu_members with
  | [] ->
      let hint =
        "No component definition found. FPP components are defined with:\n\
        \  active component Name { ... }\n\
        \  passive component Name { ... }\n\
        \  queued component Name { ... }\n\
         Make sure your .fpp file contains a component definition."
      in
      raise (Parse_error { msg = hint; file = "<input>"; line = 0; col = 0 })
  | comps -> comps

(** Find component by name, or return the only component if just one. *)
let component ?name tu =
  let comps = require_components tu in
  match name with
  | Some n -> (
      match List.find_opt (fun c -> c.Ast.comp_name.data = n) comps with
      | Some c -> c
      | None ->
          let names = List.map (fun c -> c.Ast.comp_name.data) comps in
          let hint =
            Fmt.str "Component '%s' not found. Available: %s" n
              (String.concat ", " names)
          in
          raise
            (Parse_error { msg = hint; file = "<input>"; line = 0; col = 0 }))
  | None -> (
      match comps with
      | [ c ] -> c
      | _ ->
          let names = List.map (fun c -> c.Ast.comp_name.data) comps in
          let hint =
            Fmt.str
              "Multiple components found: %s.\n\
               Use --component <name> to specify which one."
              (String.concat ", " names)
          in
          raise
            (Parse_error { msg = hint; file = "<input>"; line = 0; col = 0 }))

let rec collect_topologies members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_topology t -> [ t ]
      | Ast.Mod_def_module m -> collect_topologies m.Ast.module_members
      | _ -> [])
    members

let topologies tu = collect_topologies tu.Ast.tu_members

let rec collect_instances members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_component_instance i -> [ i ]
      | Ast.Mod_def_module m -> collect_instances m.Ast.module_members
      | _ -> [])
    members

let instances tu = collect_instances tu.Ast.tu_members

let rec collect_port_defs members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_port p -> [ p ]
      | Ast.Mod_def_module m -> collect_port_defs m.Ast.module_members
      | _ -> [])
    members

let port_defs tu = collect_port_defs tu.Ast.tu_members

let rec collect_enums members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_enum e -> [ e ]
      | Ast.Mod_def_module m -> collect_enums m.Ast.module_members
      | _ -> [])
    members

let enums tu = collect_enums tu.Ast.tu_members

let rec collect_structs members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_struct s -> [ s ]
      | Ast.Mod_def_module m -> collect_structs m.Ast.module_members
      | _ -> [])
    members

let structs tu = collect_structs tu.Ast.tu_members

let rec collect_constants members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_constant c -> [ c ]
      | Ast.Mod_def_module m -> collect_constants m.Ast.module_members
      | _ -> [])
    members

let constants tu = collect_constants tu.Ast.tu_members

let rec collect_state_machines members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_state_machine sm -> [ sm ]
      | Ast.Mod_def_module m -> collect_state_machines m.Ast.module_members
      | _ -> [])
    members

let state_machines tu = collect_state_machines tu.Ast.tu_members

(** {1 AST Helpers} *)

let type_to_string t =
  match t with
  | Ast.Type_bool -> "bool"
  | Ast.Type_int i -> (
      match i with
      | Ast.U8 -> "U8"
      | Ast.U16 -> "U16"
      | Ast.U32 -> "U32"
      | Ast.U64 -> "U64"
      | Ast.I8 -> "I8"
      | Ast.I16 -> "I16"
      | Ast.I32 -> "I32"
      | Ast.I64 -> "I64")
  | Ast.Type_float f -> ( match f with Ast.F32 -> "F32" | Ast.F64 -> "F64")
  | Ast.Type_string _ -> "string"
  | Ast.Type_qual q -> Ast.qual_ident_to_string q.Ast.data

let rec expr_to_int e =
  match e with
  | Ast.Expr_literal (Ast.Lit_int s) -> int_of_string_opt s
  | Ast.Expr_paren { data; _ } -> expr_to_int data
  | _ -> None

let rec expr_to_string e =
  match e with
  | Ast.Expr_literal (Ast.Lit_int s) -> s
  | Ast.Expr_literal (Ast.Lit_float s) -> s
  | Ast.Expr_literal (Ast.Lit_string s) -> s
  | Ast.Expr_literal (Ast.Lit_bool b) -> string_of_bool b
  | Ast.Expr_ident { data; _ } -> data
  | Ast.Expr_paren { data; _ } -> expr_to_string data
  | Ast.Expr_unop (Ast.Minus, { data; _ }) -> "-" ^ expr_to_string data
  | _ -> ""

let qual_ident_to_string = Ast.qual_ident_to_string

(** {1 Component Member Extractors} *)

open Ast

let commands comp =
  List.filter_map
    (fun (_, m, _) ->
      match m.data with Comp_spec_command c -> Some c | _ -> None)
    comp.comp_members

let ports comp =
  List.filter_map
    (fun (_, m, _) ->
      match m.data with
      | Comp_spec_port_instance (Port_general p) -> Some p
      | _ -> None)
    comp.comp_members

let events comp =
  List.filter_map
    (fun (_, m, _) ->
      match m.data with Comp_spec_event e -> Some e | _ -> None)
    comp.comp_members

let telemetry comp =
  List.filter_map
    (fun (_, m, _) ->
      match m.data with Comp_spec_tlm_channel t -> Some t | _ -> None)
    comp.comp_members

let params comp =
  List.filter_map
    (fun (_, m, _) ->
      match m.data with Comp_spec_param p -> Some p | _ -> None)
    comp.comp_members

let is_input = function
  | Async_input | Guarded_input | Sync_input -> true
  | Output -> false

let is_output = function Output -> true | _ -> false

(** Extract enums defined within a component *)
let component_enums comp =
  List.filter_map
    (fun (_, m, _) -> match m.data with Comp_def_enum e -> Some e | _ -> None)
    comp.comp_members

(** Collect enums from both module level and component level with namespace *)
let rec collect_enums_with_ns ?(ns = []) members =
  List.concat_map
    (fun ann ->
      match unannotate_node ann with
      | Mod_def_enum e -> [ (ns, e) ]
      | Mod_def_module m ->
          let new_ns = ns @ [ m.module_name.data ] in
          collect_enums_with_ns ~ns:new_ns m.module_members
      | Mod_def_component c ->
          (* Enums inside components use the component as part of namespace *)
          let comp_ns = ns @ [ c.comp_name.data ] in
          List.map (fun e -> (comp_ns, e)) (component_enums c)
      | _ -> [])
    members

let enums_with_namespace tu = collect_enums_with_ns tu.tu_members

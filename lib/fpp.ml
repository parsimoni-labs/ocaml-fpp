(** FPP Parser.

    This module provides the main entry point for parsing FPP files using the
    Menhir-generated parser. *)

module Ast = Ast
module Check = Check
module Dot = Dot

(** {1 Parse Errors} *)

type error = { msg : string; file : string; line : int; col : int }

exception Parse_error of error
exception Lexer_error = Lexer.Error

let pp_error ppf e = Fmt.pf ppf "%s:%d:%d: %s" e.file e.line e.col e.msg

(** {1 Parsing} *)

let is_contextual_keyword = function
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

let is_value_end tok =
  match tok with
  | Parser.INT _ | Parser.FLOAT _ | Parser.STRING _ | Parser.BOOL _
  | Parser.IDENT _ | Parser.PRIM_TYPE _ | Parser.RPAREN | Parser.RBRACKET
  | Parser.RBRACE ->
      true
  | tok -> is_contextual_keyword tok

let is_value_start tok =
  match tok with
  | Parser.INT _ | Parser.FLOAT _ | Parser.STRING _ | Parser.BOOL _
  | Parser.IDENT _ | Parser.PRIM_TYPE _ | Parser.LPAREN | Parser.LBRACKET
  | Parser.LBRACE | Parser.MINUS ->
      true
  | tok -> is_contextual_keyword tok

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

let error_of_pos msg pos =
  {
    msg;
    file = pos.Lexing.pos_fname;
    line = pos.Lexing.pos_lnum;
    col = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
  }

let parse_lexbuf lexbuf =
  try Parser.translation_unit (newline_aware_lexer Lexer.token) lexbuf with
  | Lexer.Error (msg, pos) -> raise (Parse_error (error_of_pos msg pos))
  | Parser.Error ->
      raise (Parse_error (error_of_pos "syntax error" lexbuf.Lexing.lex_curr_p))

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

let unannotate_node (_, node, _) = node.Ast.data

(* Generic recursive collector over module members. *)
let rec collect f members =
  List.concat_map
    (fun ann ->
      match f (unannotate_node ann) with
      | Some x -> [ x ]
      | None -> (
          match unannotate_node ann with
          | Ast.Mod_def_module m -> collect f m.Ast.module_members
          | _ -> []))
    members

let modules tu =
  List.filter_map
    (fun ann ->
      match unannotate_node ann with
      | Ast.Mod_def_module m -> Some m
      | _ -> None)
    tu.Ast.tu_members

let components tu =
  collect
    (function Ast.Mod_def_component c -> Some c | _ -> None)
    tu.Ast.tu_members

let rec collect_with_ns f ?(ns = []) members =
  List.concat_map
    (fun ann ->
      match f ns (unannotate_node ann) with
      | Some x -> [ x ]
      | None -> (
          match unannotate_node ann with
          | Ast.Mod_def_module m ->
              let ns = ns @ [ m.Ast.module_name.data ] in
              collect_with_ns f ~ns m.Ast.module_members
          | _ -> []))
    members

let components_with_namespace tu =
  collect_with_ns
    (fun ns -> function Ast.Mod_def_component c -> Some (ns, c) | _ -> None)
    tu.Ast.tu_members

let component_namespace tu comp =
  let pairs = components_with_namespace tu in
  match
    List.find_opt
      (fun (_, c) -> c.Ast.comp_name.data = comp.Ast.comp_name.data)
      pairs
  with
  | Some (ns, _) -> String.concat "::" ns
  | None -> ""

let require_components tu =
  match components tu with
  | [] ->
      raise
        (Parse_error
           {
             msg =
               "No component definition found. FPP components are defined with:\n\
               \  active component Name { ... }\n\
               \  passive component Name { ... }\n\
               \  queued component Name { ... }\n\
                Make sure your .fpp file contains a component definition.";
             file = "<input>";
             line = 0;
             col = 0;
           })
  | comps -> comps

let component ?name tu =
  let comps = require_components tu in
  match name with
  | Some n -> (
      match List.find_opt (fun c -> c.Ast.comp_name.data = n) comps with
      | Some c -> c
      | None ->
          let names = List.map (fun c -> c.Ast.comp_name.data) comps in
          raise
            (Parse_error
               {
                 msg =
                   Fmt.str "Component '%s' not found. Available: %s" n
                     (String.concat ", " names);
                 file = "<input>";
                 line = 0;
                 col = 0;
               }))
  | None -> (
      match comps with
      | [ c ] -> c
      | _ ->
          let names = List.map (fun c -> c.Ast.comp_name.data) comps in
          raise
            (Parse_error
               {
                 msg =
                   Fmt.str
                     "Multiple components found: %s.\n\
                      Use --component <name> to specify which one."
                     (String.concat ", " names);
                 file = "<input>";
                 line = 0;
                 col = 0;
               }))

let topologies tu =
  collect
    (function Ast.Mod_def_topology t -> Some t | _ -> None)
    tu.Ast.tu_members

let instances tu =
  collect
    (function Ast.Mod_def_component_instance i -> Some i | _ -> None)
    tu.Ast.tu_members

let port_defs tu =
  collect
    (function Ast.Mod_def_port p -> Some p | _ -> None)
    tu.Ast.tu_members

let enums tu =
  collect
    (function Ast.Mod_def_enum e -> Some e | _ -> None)
    tu.Ast.tu_members

let structs tu =
  collect
    (function Ast.Mod_def_struct s -> Some s | _ -> None)
    tu.Ast.tu_members

let constants tu =
  collect
    (function Ast.Mod_def_constant c -> Some c | _ -> None)
    tu.Ast.tu_members

let state_machines tu =
  collect
    (function Ast.Mod_def_state_machine sm -> Some sm | _ -> None)
    tu.Ast.tu_members

(** {1 AST Helpers} *)

let type_to_string = function
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

let rec expr_to_int = function
  | Ast.Expr_literal (Ast.Lit_int s) -> int_of_string_opt s
  | Ast.Expr_paren { data; _ } -> expr_to_int data
  | _ -> None

let rec expr_to_string = function
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

let filter_comp_members f comp =
  List.filter_map (fun (_, m, _) -> f m.Ast.data) comp.Ast.comp_members

let commands comp =
  filter_comp_members
    (function Ast.Comp_spec_command c -> Some c | _ -> None)
    comp

let ports comp =
  filter_comp_members
    (function
      | Ast.Comp_spec_port_instance (Ast.Port_general p) -> Some p | _ -> None)
    comp

let events comp =
  filter_comp_members
    (function Ast.Comp_spec_event e -> Some e | _ -> None)
    comp

let telemetry comp =
  filter_comp_members
    (function Ast.Comp_spec_tlm_channel t -> Some t | _ -> None)
    comp

let params comp =
  filter_comp_members
    (function Ast.Comp_spec_param p -> Some p | _ -> None)
    comp

let is_input = function
  | Ast.Async_input | Ast.Guarded_input | Ast.Sync_input -> true
  | Ast.Output -> false

let is_output = function Ast.Output -> true | _ -> false

let component_enums comp =
  filter_comp_members
    (function Ast.Comp_def_enum e -> Some e | _ -> None)
    comp

let enums_with_namespace tu =
  collect_with_ns
    (fun ns -> function
      | Ast.Mod_def_enum e -> Some (ns, e)
      | Ast.Mod_def_component c ->
          let comp_ns = ns @ [ c.Ast.comp_name.data ] in
          (* Return first enum if any; the rest are handled by concat_map *)
          ignore comp_ns;
          None
      | _ -> None)
    tu.Ast.tu_members
  @
  (* Also collect enums inside components *)
  List.concat_map
    (fun (ns, c) ->
      let comp_ns = ns @ [ c.Ast.comp_name.data ] in
      List.map (fun e -> (comp_ns, e)) (component_enums c))
    (components_with_namespace tu)

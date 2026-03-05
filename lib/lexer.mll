(** FPP Lexer. *)
{
open Parser

exception Error of string * Lexing.position

let error lexbuf msg = raise (Error (msg, lexbuf.Lexing.lex_start_p))

let string_buf = Buffer.create 256

(* Track whether a newline was crossed between tokens.
   Used by the parser wrapper to insert virtual commas in array literals. *)
let _saw_newline = ref false
let saw_newline () = let v = !_saw_newline in _saw_newline := false; v
let reset () = _saw_newline := false

let newline lexbuf =
  _saw_newline := true;
  let pos = lexbuf.Lexing.lex_curr_p in
  lexbuf.Lexing.lex_curr_p <- { pos with
    Lexing.pos_lnum = pos.Lexing.pos_lnum + 1;
    Lexing.pos_bol = pos.Lexing.pos_cnum;
  }

let keywords = Hashtbl.create 64
let () = List.iter (fun (kw, tok) -> Hashtbl.add keywords kw tok) [
  "active", ACTIVE; "passive", PASSIVE; "queued", QUEUED;
  "action", ACTION; "array", ARRAY; "block", BLOCK;
  "choice", CHOICE; "command", COMMAND; "component", COMPONENT;
  "connections", CONNECTIONS; "constant", CONSTANT; "container", CONTAINER;
  "default", DEFAULT; "dictionary", DICTIONARY; "do", DO; "else", ELSE; "enter", ENTER; "entry", ENTRY;
  "enum", ENUM; "event", EVENT; "exit", EXIT; "external", EXTERNAL;
  "guard", GUARD; "health", HEALTH; "hook", HOOK;
  "if", IF; "import", IMPORT; "include", INCLUDE; "initial", INITIAL;
  "input", INPUT; "instance", INSTANCE; "interface", INTERFACE;
  "internal", INTERNAL; "locate", LOCATE; "match", MATCH; "module", MODULE;
  "opcode", OPCODE; "output", OUTPUT; "packet", PACKET; "packets", PACKETS;
  "param", PARAM; "phase", PHASE; "port", PORT; "priority", PRIORITY;
  "private", PRIVATE; "product", PRODUCT; "public", PUBLIC;
  "record", RECORD; "recv", RECV; "ref", REF; "reg", REG;
  "request", REQUEST; "resp", RESP; "save", SAVE; "send", SEND;
  "serial", SERIAL;
  "set", SET; "get", GET; "severity", SEVERITY; "signal", SIGNAL;
  "size", SIZE; "state", STATE; "struct", STRUCT;
  "telemetry", TELEMETRY; "text", TEXT; "throttle", THROTTLE;
  "time", TIME; "topology", TOPOLOGY;
  "type", TYPE; "unmatched", UNMATCHED; "update", UPDATE; "with", WITH;
  "async", ASYNC; "sync", SYNC; "guarded", GUARDED;
  "fatal", FATAL; "warning", WARNING; "activity", ACTIVITY;
  "diagnostic", DIAGNOSTIC; "high", HIGH; "low", LOW;
  "always", ALWAYS; "change", CHANGE; "on", ON;
  "red", RED; "orange", ORANGE; "yellow", YELLOW;
  "assert", ASSERT; "at", AT; "base", BASE; "cpu", CPU; "drop", DROP;
  "every", EVERY; "format", FORMAT; "group", GROUP; "id", ID;
  "machine", MACHINE; "omit", OMIT; "queue", QUEUE; "seconds", SECONDS;
  "stack", STACK;
  "true", BOOL true; "false", BOOL false;
  "U8", PRIM_TYPE "U8"; "U16", PRIM_TYPE "U16"; "U32", PRIM_TYPE "U32";
  "U64", PRIM_TYPE "U64"; "I8", PRIM_TYPE "I8"; "I16", PRIM_TYPE "I16";
  "I32", PRIM_TYPE "I32"; "I64", PRIM_TYPE "I64";
  "F32", PRIM_TYPE "F32"; "F64", PRIM_TYPE "F64";
  "bool", PRIM_TYPE "bool"; "string", STRING_KW;
]

let lookup_ident s =
  try Hashtbl.find keywords s with Not_found -> IDENT s
}

let digit = ['0'-'9']
let hex = ['0'-'9' 'a'-'f' 'A'-'F']
let alpha = ['a'-'z' 'A'-'Z']
let ident_start = alpha | '_' | '$'
let ident_char = alpha | digit | '_'
let int_lit = digit+ | "0x" hex+ | "0X" hex+
let float_lit = digit+ '.' digit* | '.' digit+
let ident = ident_start ident_char*
let white = [' ' '\t']+
let newline = '\r'? '\n'

rule token = parse
  | white       { token lexbuf }
  | newline     { newline lexbuf; token lexbuf }
  | '\\' newline { let saved = !_saw_newline in newline lexbuf; _saw_newline := saved; token lexbuf }
  | '#' [^ '\n']* { token lexbuf }
  | ';'         { token lexbuf } (* FPP allows optional semicolons *)
  | '@' white? '<' { annotation_post lexbuf }
  | '@'         { annotation_pre lexbuf }
  | '{'         { LBRACE }
  | '}'         { RBRACE }
  | '['         { LBRACKET }
  | ']'         { RBRACKET }
  | '('         { LPAREN }
  | ')'         { RPAREN }
  | ':'         { COLON }
  | ','         { COMMA }
  | '.'         { DOT }
  | '='         { EQUALS }
  | "->"        { ARROW }
  | '+'         { PLUS }
  | '-'         { MINUS }
  | '*'         { STAR }
  | '/'         { SLASH }
  | "\"\"\""    { Buffer.clear string_buf; multiline_string lexbuf; STRING (Buffer.contents string_buf) }
  | '"'         { Buffer.clear string_buf; string_literal lexbuf; STRING (Buffer.contents string_buf) }
  | float_lit as f { FLOAT f }
  | int_lit as i   { INT i }
  | ident as id    { lookup_ident id }
  | eof         { EOF }
  | _ as c      { error lexbuf (Printf.sprintf "unexpected character: %c" c) }

and string_literal = parse
  | '"'         { () }
  | '\\' 'n'    { Buffer.add_char string_buf '\n'; string_literal lexbuf }
  | '\\' 't'    { Buffer.add_char string_buf '\t'; string_literal lexbuf }
  | '\\' 'r'    { Buffer.add_char string_buf '\r'; string_literal lexbuf }
  | '\\' '\\'   { Buffer.add_char string_buf '\\'; string_literal lexbuf }
  | '\\' '"'    { Buffer.add_char string_buf '"'; string_literal lexbuf }
  | newline     { error lexbuf "unterminated string" }
  | eof         { error lexbuf "unterminated string" }
  | _ as c      { Buffer.add_char string_buf c; string_literal lexbuf }

and multiline_string = parse
  | "\"\"\""    { () }
  | newline     { newline lexbuf; Buffer.add_char string_buf '\n'; multiline_string lexbuf }
  | eof         { error lexbuf "unterminated multiline string" }
  | _ as c      { Buffer.add_char string_buf c; multiline_string lexbuf }

and annotation_pre = parse
  | white       { annotation_pre lexbuf }
  | newline     { newline lexbuf; ANNOTATION_PRE "" }
  | [^ '\n']* as s { ANNOTATION_PRE (String.trim s) }

and annotation_post = parse
  | white       { annotation_post lexbuf }
  | newline     { newline lexbuf; ANNOTATION_POST "" }
  (* Post-annotations run to end of line - don't stop at delimiters *)
  | [^ '\n']* as s { ANNOTATION_POST (String.trim s) }

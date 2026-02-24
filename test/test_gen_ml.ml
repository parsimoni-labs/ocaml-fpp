(** Tests for {!Fpp.Gen_ml}: state machine to OCaml code generation. *)

let parse s =
  match Fpp.parse_string s with
  | tu -> tu
  | exception Fpp.Parse_error e ->
      Alcotest.failf "parse error: %a" Fpp.pp_error e

let render s =
  let tu = parse s in
  let sms = Fpp.state_machines tu in
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  List.iter (fun sm -> Fpp.Gen_ml.pp ppf sm) sms;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

let contains ~substr s =
  let len = String.length substr in
  let slen = String.length s in
  if len > slen then false
  else
    let found = ref false in
    for i = 0 to slen - len do
      if String.sub s i len = substr then found := true
    done;
    !found

(* ── Basic generation ─────────────────────────────────────────────── *)

let test_simple_sm () =
  let ml =
    render
      {|
    state machine M {
      signal s
      initial enter S1
      state S1 { on s enter S2 }
      state S2
    }
  |}
  in
  Alcotest.(check bool) "phantom types" true (contains ~substr:"type s1" ml);
  Alcotest.(check bool) "state GADT" true (contains ~substr:"_ state =" ml);
  Alcotest.(check bool)
    "existential" true
    (contains ~substr:"type any = State" ml);
  Alcotest.(check bool) "module Make" true (contains ~substr:"module Make" ml);
  Alcotest.(check bool) "let create" true (contains ~substr:"let create" ml);
  Alcotest.(check bool) "let step" true (contains ~substr:"let step" ml)

let test_typed_signal () =
  let ml =
    render
      {|
    state machine M {
      signal s : U32
      initial enter S
      state S { on s enter S }
    }
  |}
  in
  Alcotest.(check bool) "signal type" true (contains ~substr:"type signal" ml);
  Alcotest.(check bool)
    "signal with data" true
    (contains ~substr:"S of int32" ml)

let test_guard_choice () =
  let ml =
    render
      {|
    state machine M {
      action a1
      guard g
      signal s
      initial enter C
      state S
      choice C { if g do { a1 } enter S else enter S }
    }
  |}
  in
  Alcotest.(check bool)
    "ACTIONS module type" true
    (contains ~substr:"ACTIONS" ml);
  Alcotest.(check bool) "GUARDS module type" true (contains ~substr:"GUARDS" ml);
  Alcotest.(check bool) "enter_c function" true (contains ~substr:"enter_c" ml)

let test_nested_state () =
  let ml =
    render
      {|
    state machine M {
      initial enter S
      state S {
        initial enter T
        state T
      }
    }
  |}
  in
  Alcotest.(check bool) "leaf phantom type" true (contains ~substr:"type t" ml);
  Alcotest.(check bool)
    "leaf state GADT" true
    (contains ~substr:"| T : t state" ml);
  Alcotest.(check bool)
    "create resolves to leaf" true
    (contains ~substr:"State T" ml)

let test_door () =
  let ml =
    render
      {|
    state machine Door {
      action lock
      guard locked
      signal open
      signal close
      initial enter Closed
      state Closed { on open if locked enter Closed
                     on open enter Opened }
      state Opened { on close do { lock } enter Closed }
    }
  |}
  in
  Alcotest.(check bool)
    "phantom closed" true
    (contains ~substr:"type closed" ml);
  Alcotest.(check bool)
    "phantom opened" true
    (contains ~substr:"type opened" ml);
  Alcotest.(check bool) "State Closed" true (contains ~substr:"State Closed" ml);
  Alcotest.(check bool) "State Opened" true (contains ~substr:"State Opened" ml);
  Alcotest.(check bool) "G.locked" true (contains ~substr:"G.locked" ml);
  Alcotest.(check bool) "A.lock" true (contains ~substr:"A.lock" ml)

(* ── Topology generation ──────────────────────────────────────────── *)

let render_topo s =
  let tu = parse s in
  let topos = Fpp.topologies tu in
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  List.iter (fun topo -> Fpp.Gen_ml.pp_topology tu ppf topo) topos;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

let test_simple_topology () =
  let ml =
    render_topo
      {|
    port P
    passive component Sensor { output port dataOut: P }
    passive component Logger { sync input port dataIn: P }
    instance sensor: Sensor base id 0x100
    instance logger: Logger base id 0x200
    topology System {
      instance sensor
      instance logger
      connections Data { sensor.dataOut -> logger.dataIn }
    }
  |}
  in
  (* No port module types — only component module types *)
  Alcotest.(check bool)
    "no module type P" false
    (contains ~substr:"module type P =" ml);
  Alcotest.(check bool) "no val send" false (contains ~substr:"val send" ml);
  (* Component module types just have type t *)
  Alcotest.(check bool)
    "SENSOR module type" true
    (contains ~substr:"module type SENSOR = sig" ml);
  Alcotest.(check bool)
    "LOGGER module type" true
    (contains ~substr:"module type LOGGER = sig" ml);
  (* Logger is a leaf (no outgoing connections) — plain module type *)
  Alcotest.(check bool)
    "Logger param" true
    (contains ~substr:"(Logger : LOGGER)" ml);
  (* Sensor has output port — inline connect constraint *)
  Alcotest.(check bool)
    "Sensor inline connect" true
    (contains ~substr:"(Sensor : sig include SENSOR val connect :" ml);
  Alcotest.(check bool)
    "Sensor connect takes Logger.t" true
    (contains ~substr:"Logger.t -> t end)" ml);
  (* Leaf params become connect args *)
  Alcotest.(check bool)
    "connect logger" true
    (contains ~substr:"let connect logger" ml);
  (* No functor application or adapter struct *)
  Alcotest.(check bool) "no create" false (contains ~substr:"val create" ml);
  Alcotest.(check bool)
    "no adapter struct" false
    (contains ~substr:"(struct" ml)

let test_typed_port_topology () =
  let ml =
    render_topo
      {|
    port DataPort(value: U32) -> bool
    passive component Producer { output port out: DataPort }
    passive component Consumer { sync input port in_: DataPort }
    instance producer: Producer base id 0x100
    instance consumer: Consumer base id 0x200
    topology App {
      instance producer
      instance consumer
      connections Main { producer.out -> consumer.in_ }
    }
  |}
  in
  (* No port module types *)
  Alcotest.(check bool)
    "no DATA_PORT module type" false
    (contains ~substr:"module type DATA_PORT" ml);
  (* Consumer is leaf — plain module type *)
  Alcotest.(check bool)
    "Consumer : CONSUMER" true
    (contains ~substr:"(Consumer : CONSUMER)" ml);
  (* Producer has output — inline connect constraint *)
  Alcotest.(check bool)
    "Producer inline connect" true
    (contains ~substr:"(Producer : sig include PRODUCER val connect :" ml);
  Alcotest.(check bool)
    "Producer connect takes Consumer.t" true
    (contains ~substr:"Consumer.t -> t end)" ml)

(* ── Annotated (functor-application) topology ───────────────────────── *)

let test_annotated_topology () =
  let ml =
    render_topo
      {|
    port P
    active component Net { sync input port write: P }
    @ ocaml.functor Eth.Make
    active component Ethernet {
      output port net: P
      sync input port write: P
    }
    @ ocaml.functor Ipv4.Make
    active component Ipv4 {
      output port eth: P
      sync input port write: P
      @ ocaml.param
      sync input port cidr: P
    }
    instance net: Net base id 0x100
    instance eth: Ethernet base id 0x200
    instance ipv4: Ipv4 base id 0x300
    topology Stack {
      instance net
      instance eth
      instance ipv4
      connections W {
        eth.net -> net.write
        ipv4.eth -> eth.write
      }
    }
  |}
  in
  (* Leaf parameter uses generated module type alias *)
  Alcotest.(check bool) "Net : NET" true (contains ~substr:"(Net : NET)" ml);
  (* Functor applications inside struct *)
  Alcotest.(check bool)
    "module Eth = Eth.Make(Net)" true
    (contains ~substr:"module Eth = Eth.Make(Net)" ml);
  Alcotest.(check bool)
    "module Ipv4 = Ipv4.Make(Eth)" true
    (contains ~substr:"module Ipv4 = Ipv4.Make(Eth)" ml);
  (* ocaml.param port surfaces as labeled arg *)
  Alcotest.(check bool)
    "connect ~cidr" true
    (contains ~substr:"let connect ~cidr net" ml);
  (* ocaml.param passed through to connect call *)
  Alcotest.(check bool)
    "Ipv4.connect ~cidr" true
    (contains ~substr:"Ipv4.connect ~cidr eth" ml);
  (* Unannotated unconnected port does NOT surface *)
  Alcotest.(check bool) "no ~write param" false (contains ~substr:"~write" ml);
  (* Module type alias NOT emitted by pp_topology (emitted by pp_module_types) *)
  Alcotest.(check bool)
    "no module type in topology output" false
    (contains ~substr:"module type NET" ml)

let test_annotated_default_functor () =
  let ml =
    render_topo
      {|
    port P
    @ ocaml.functor Foo.Make
    active component Foo {
      output port out: P
    }
    active component Bar {
      sync input port in_: P
    }
    instance foo: Foo base id 0x100
    instance bar: Bar base id 0x200
    topology T {
      instance foo
      instance bar
      connections C { foo.out -> bar.in_ }
    }
  |}
  in
  (* Bar's constraint is generated from its ports *)
  Alcotest.(check bool) "Bar : BAR" true (contains ~substr:"(Bar : BAR)" ml);
  (* Foo uses explicit annotation *)
  Alcotest.(check bool)
    "module Foo = Foo.Make(Bar)" true
    (contains ~substr:"module Foo = Foo.Make(Bar)" ml)

(* ── External types ──────────────────────────────────────────────── *)

let render_module_types s =
  let tu = parse s in
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  Fpp.Gen_ml.pp_module_types tu ppf;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

let test_external_types () =
  let ml =
    render_module_types
      {|
    @ ocaml.type Cstruct.t
    type Buffer
    type Macaddr
    port Write(data: Buffer)
    port GetMac -> Macaddr
    active component Net {
      sync input port write: Write
      sync input port mac: GetMac
    }
    active component Eth {
      output port net: Write
      sync input port write: Write
    }
    instance net: Net base id 0x100
    instance eth: Eth base id 0x200
    topology T {
      instance net
      instance eth
      connections C { eth.net -> net.write }
    }
  |}
  in
  (* External type with @ ocaml.type annotation *)
  Alcotest.(check bool)
    "Cstruct.t in write" true
    (contains ~substr:"Cstruct.t" ml);
  (* External type with default Name.t convention *)
  Alcotest.(check bool)
    "Macaddr.t in mac" true
    (contains ~substr:"Macaddr.t" ml);
  (* Not the FPP-default camel_to_snake *)
  Alcotest.(check bool)
    "no buffer lowercase" false
    (contains ~substr:"buffer" ml)

(* ── Suite ──────────────────────────────────────────────────────────── *)

let suite =
  ( "gen_ml",
    [
      Alcotest.test_case "simple_sm" `Quick test_simple_sm;
      Alcotest.test_case "typed_signal" `Quick test_typed_signal;
      Alcotest.test_case "guard_choice" `Quick test_guard_choice;
      Alcotest.test_case "nested_state" `Quick test_nested_state;
      Alcotest.test_case "door" `Quick test_door;
      Alcotest.test_case "simple_topology" `Quick test_simple_topology;
      Alcotest.test_case "typed_port_topology" `Quick test_typed_port_topology;
      Alcotest.test_case "annotated_topology" `Quick test_annotated_topology;
      Alcotest.test_case "annotated_default_functor" `Quick
        test_annotated_default_functor;
      Alcotest.test_case "external_types" `Quick test_external_types;
    ] )

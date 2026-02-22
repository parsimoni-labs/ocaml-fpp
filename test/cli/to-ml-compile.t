Generated OCaml from state machines and topologies must compile and run correctly.

Setup: create a dune-project so we can build with dune
  $ cat > dune-project <<EOF
  > (lang dune 3.0)
  > EOF
  $ cat > dune <<EOF
  > (executable (name sm) (ocamlopt_flags (:standard -w -23)))
  > EOF

Simple state machines (no actions or guards)
  $ cat > t.fpp <<EOF
  > state machine M {
  >   state S
  >   initial enter S
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > let () =
  >   let m = Make.create () in
  >   let State _ = Make.state m in
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "state_ok: OK"
  state_ok: OK

  $ cat > t.fpp <<EOF
  > state machine M {
  >   initial enter S
  >   state S {
  >     initial enter T
  >     state T
  >   }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > let () =
  >   let m = Make.create () in
  >   assert (Make.state m = State T);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "nested_state_ok: OK"
  nested_state_ok: OK

  $ cat > t.fpp <<EOF
  > state machine M {
  >   state S1 {
  >     initial enter S1
  >     state S1
  >   }
  >   initial enter S1
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > let () =
  >   let m = Make.create () in
  >   assert (Make.state m = State S1);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "state_shadow_ok: OK"
  state_shadow_ok: OK

Signal dispatch
  $ cat > t.fpp <<EOF
  > state machine M {
  >   signal s
  >   initial enter S
  >   state S { on s enter S }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > let () =
  >   let m = Make.create () in
  >   let m = Make.step m S in
  >   assert (Make.state m = State S);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "signal_ok: OK"
  signal_ok: OK

  $ cat > t.fpp <<EOF
  > state machine M {
  >   guard g
  >   signal s
  >   initial enter S
  >   state S {
  >     on s enter C
  >     choice C { if g enter S1 else enter S2 }
  >   }
  >   state S1 { on s enter S }
  >   state S2
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module G = struct
  >   type ctx = { mutable flag : bool }
  >   let g ctx = ctx.flag
  > end
  > module M = Make (G)
  > let () =
  >   let ctx = G.{ flag = true } in
  >   let m = M.create ctx in
  >   assert (M.state m = State S);
  >   let m = M.step m S in
  >   assert (M.state m = State S1);
  >   let m = M.step m S in
  >   assert (M.state m = State S);
  >   ctx.flag <- false;
  >   let m = M.step m S in
  >   assert (M.state m = State S2);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "cycle_ok: OK"
  cycle_ok: OK

Actions
  $ cat > t.fpp <<EOF
  > state machine M {
  >   action a
  >   state S
  >   initial do { a } enter S
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module A = struct
  >   type ctx = { mutable called : bool }
  >   let a ctx = ctx.called <- true
  > end
  > module M = Make (A)
  > let () =
  >   let ctx = A.{ called = false } in
  >   let m = M.create ctx in
  >   assert ctx.A.called;
  >   assert (M.state m = State S);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "action_ok: OK"
  action_ok: OK

  $ cat > t.fpp <<EOF
  > state machine M {
  >   action a
  >   initial enter S
  >   state S {
  >     initial do { a } enter T
  >     state T
  >   }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module A = struct
  >   type ctx = { mutable called : bool }
  >   let a ctx = ctx.called <- true
  > end
  > module M = Make (A)
  > let () =
  >   let ctx = A.{ called = false } in
  >   let m = M.create ctx in
  >   assert ctx.A.called;
  >   assert (M.state m = State T);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "nested_action_ok: OK"
  nested_action_ok: OK

Guards and choices
  $ cat > t.fpp <<EOF
  > state machine M {
  >   guard g
  >   state S
  >   initial enter C
  >   choice C { if g enter S else enter S }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module G = struct
  >   type ctx = unit
  >   let g () = true
  > end
  > module M = Make (G)
  > let () =
  >   let m = M.create () in
  >   assert (M.state m = State S);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "choice_ok: OK"
  choice_ok: OK

  $ cat > t.fpp <<EOF
  > state machine M {
  >   guard g
  >   initial enter S
  >   state S {
  >     state T
  >     initial enter C
  >     choice C { if g enter T else enter T }
  >   }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module G = struct
  >   type ctx = unit
  >   let g () = true
  > end
  > module M = Make (G)
  > let () =
  >   let m = M.create () in
  >   assert (M.state m = State T);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "nested_choice_ok: OK"
  nested_choice_ok: OK

  $ cat > t.fpp <<EOF
  > state machine M {
  >   guard g
  >   initial enter S
  >   state S {
  >     initial enter C
  >     choice C { if g enter T else enter T }
  >     state T
  >   }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module G = struct
  >   type ctx = unit
  >   let g () = false
  > end
  > module M = Make (G)
  > let () =
  >   let m = M.create () in
  >   assert (M.state m = State T);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "nested_guard_ok: OK"
  nested_guard_ok: OK

Door (actions + guards + signals, full workflow)
  $ cat > t.fpp <<EOF
  > state machine Door {
  >   action lock
  >   guard locked
  >   signal open
  >   signal close
  >   initial enter Closed
  >   state Closed { on open if locked enter Closed
  >                  on open enter Opened }
  >   state Opened { on close do { lock } enter Closed }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module Actions = struct
  >   type ctx = { mutable is_locked : bool }
  >   let lock ctx = ctx.is_locked <- true
  > end
  > module Guards = struct
  >   type ctx = Actions.ctx
  >   let locked ctx = ctx.Actions.is_locked
  > end
  > module D = Make (Actions) (Guards)
  > let () =
  >   let ctx = { Actions.is_locked = false } in
  >   let d = D.create ctx in
  >   assert (D.state d = State Closed);
  >   let d = D.step d Open in
  >   assert (D.state d = State Opened);
  >   let d = D.step d Close in
  >   assert (D.state d = State Closed);
  >   assert ctx.Actions.is_locked;
  >   let d = D.step d Open in
  >   assert (D.state d = State Closed);
  >   ignore d
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "door: OK"
  door: OK

Enum + array types used by signals and actions
  $ cat > t.fpp <<EOF
  > state machine Motor {
  >   enum Direction { FORWARD, BACKWARD, STOPPED }
  >   array History = [4] Direction
  >   action apply: Direction
  >   signal cmd: Direction
  >   initial enter Idle
  >   state Idle    { on cmd do { apply } enter Running }
  >   state Running { on cmd do { apply } enter Idle }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module A = struct
  >   type ctx = { mutable dir : direction }
  >   let apply ctx d = ctx.dir <- d
  > end
  > module M = Make (A)
  > let () =
  >   let ctx = A.{ dir = Stopped } in
  >   let m = M.create ctx in
  >   assert (M.state m = State Idle);
  >   let m = M.step m (Cmd Forward) in
  >   assert (M.state m = State Running);
  >   assert (ctx.dir = Forward);
  >   let m = M.step m (Cmd Stopped) in
  >   assert (M.state m = State Idle);
  >   assert (ctx.dir = Stopped);
  >   let h : history = [| Forward; Backward; Stopped; Forward |] in
  >   assert (Array.length h = 4);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "motor: OK"
  motor: OK

Struct types used by signals and actions
  $ cat > t.fpp <<EOF
  > state machine Sensor {
  >   struct Reading { temp: U32, pressure: U32 }
  >   action logReading: Reading
  >   signal sample: Reading
  >   initial enter Idle
  >   state Idle   { on sample do { logReading } enter Active }
  >   state Active { on sample do { logReading } enter Idle }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module A = struct
  >   type ctx = { mutable last : reading option }
  >   let log_reading ctx r = ctx.last <- Some r
  > end
  > module S = Make (A)
  > let () =
  >   let ctx = A.{ last = None } in
  >   let m = S.create ctx in
  >   assert (S.state m = State Idle);
  >   let r1 : reading = { temp = 25l; pressure = 1013l } in
  >   let m = S.step m (Sample r1) in
  >   assert (S.state m = State Active);
  >   assert (ctx.last = Some r1);
  >   let r2 : reading = { temp = 200l; pressure = 900l } in
  >   let m = S.step m (Sample r2) in
  >   assert (S.state m = State Idle);
  >   assert (ctx.last = Some r2);
  >   ignore m
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "sensor: OK"
  sensor: OK

Topology: simple 2-component wiring
  $ cat > t.fpp <<EOF
  > port P
  > passive component Sensor {
  >   output port dataOut: P
  > }
  > passive component Logger {
  >   sync input port dataIn: P
  > }
  > instance sensor: Sensor base id 0x100
  > instance logger: Logger base id 0x200
  > topology System {
  >   instance sensor
  >   instance logger
  >   connections Data {
  >     sensor.dataOut -> logger.dataIn
  >   }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module MyLogger = struct
  >   type t = { mutable received : int }
  >   let data_in t () = t.received <- t.received + 1
  >   let connect () = { received = 0 }
  > end
  > module MySensor (Data_out : P) = struct
  >   type t = { out : Data_out.t }
  >   let trigger t = Data_out.send t.out ()
  >   let connect out = { out }
  > end
  > module App = Make (MyLogger) (MySensor)
  > let () =
  >   let app = App.connect () in
  >   App.Sensor.trigger app.sensor;
  >   assert (app.logger.received = 1);
  >   print_endline "topo: OK"
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "topo_compile: OK"
  File "sm.ml", line 45, characters 2-20:
  45 |   App.Sensor.trigger app.sensor;
         ^^^^^^^^^^^^^^^^^^
  Error: Unbound value App.Sensor.trigger
  [1]

Topology: typed port wiring compiles and field access works
  $ cat > t.fpp <<EOF
  > port DataPort(value: U32) -> bool
  > passive component Producer {
  >   output port out: DataPort
  > }
  > passive component Consumer {
  >   sync input port in_: DataPort
  > }
  > instance producer: Producer base id 0x100
  > instance consumer: Consumer base id 0x200
  > topology App {
  >   instance producer
  >   instance consumer
  >   connections Main {
  >     producer.out -> consumer.in_
  >   }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module MyConsumer = struct
  >   type t = { mutable last : int32 }
  >   let in_ t v = t.last <- v; true
  >   let connect () = { last = 0l }
  > end
  > module MyProducer (Out : DATA_PORT) = struct
  >   type t = { out : Out.t }
  >   let connect out = { out }
  > end
  > module A = Make (MyConsumer) (MyProducer)
  > let () =
  >   let app = A.connect () in
  >   let _c : MyConsumer.t = app.consumer in
  >   print_endline "typed_topo: OK"
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "typed_topo_compile: OK"
  File "sm.ml", line 5, characters 2-31:
  5 |   val send : t -> int32 -> bool
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error (warning 32 [unused-value-declaration]): unused value send.
  [1]

Topology + SM merged in one file compiles
  $ cat > t.fpp <<EOF
  > state machine Counter {
  >   signal tick
  >   initial enter Idle
  >   state Idle { on tick enter Active }
  >   state Active
  > }
  > port P
  > passive component Sensor { output port dataOut: P }
  > passive component Logger { sync input port dataIn: P }
  > instance sensor: Sensor base id 0x100
  > instance logger: Logger base id 0x200
  > topology System {
  >   instance sensor
  >   instance logger
  >   connections Data { sensor.dataOut -> logger.dataIn }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module MyLogger = struct
  >   type t = unit
  >   let data_in () () = ()
  >   let connect () = ()
  > end
  > module MySensor (Data_out : System.P) = struct
  >   type t = unit
  >   let connect _out = ()
  > end
  > module App = System.Make (MyLogger) (MySensor)
  > let () =
  >   let m = Counter.Make.create () in
  >   assert (Counter.Make.state m = Counter.State Counter.Idle);
  >   let m = Counter.Make.step m Counter.Tick in
  >   assert (Counter.Make.state m = Counter.State Counter.Active);
  >   let _app = App.connect () in
  >   print_endline "merged: OK"
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "merged_compile: OK"
  File "sm.ml", line 40, characters 2-30:
  40 |   val send : t -> unit -> unit
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error (warning 32 [unused-value-declaration]): unused value send.
  [1]

Full pipeline: SM + topology wiring
  $ cat > t.fpp <<EOF
  > state machine SensorFsm {
  >   action sample
  >   signal tick
  >   signal shutdown
  >   initial enter Idle
  >   state Idle { on tick do { sample } enter Sampling }
  >   state Sampling {
  >     on tick do { sample } enter Sampling
  >     on shutdown enter Off
  >   }
  >   state Off
  > }
  > port DataPort(temp: U32, pressure: U32)
  > port AlertPort(msg: string)
  > passive component Logger {
  >   sync input port alert: AlertPort
  > }
  > passive component Filter {
  >   output port alert: AlertPort
  >   sync input port data: DataPort
  > }
  > passive component Sensor {
  >   output port data: DataPort
  > }
  > instance logger: Logger base id 0x100
  > instance filter: Filter base id 0x200
  > instance sensor: Sensor base id 0x300
  > topology Pipeline {
  >   instance logger
  >   instance filter
  >   instance sensor
  >   connections Data {
  >     sensor.data -> filter.data
  >     filter.alert -> logger.alert
  >   }
  > }
  > EOF
  $ ofpp to-ml t.fpp > sm.ml
  $ cat >> sm.ml <<'IMPL'
  > module MyLogger = struct
  >   type t = { mutable count : int }
  >   let alert t msg =
  >     t.count <- t.count + 1;
  >     Printf.printf "  ALERT #%d: %s\n" t.count msg
  >   let connect () = { count = 0 }
  > end
  > module MyFilter (Alert : Pipeline.ALERT_PORT) = struct
  >   type t = { alert : Alert.t }
  >   let data t temp pressure =
  >     if temp > 100l then
  >       Alert.send t.alert (Printf.sprintf "Temp %ld exceeds limit" temp);
  >     if pressure < 900l then
  >       Alert.send t.alert (Printf.sprintf "Pressure %ld below min" pressure)
  >   let connect alert = { alert }
  > end
  > module MySensor (Data : Pipeline.DATA_PORT) = struct
  >   type t = { data : Data.t }
  >   let sample t temp pressure = Data.send t.data temp pressure
  >   let connect data = { data }
  > end
  > module App = Pipeline.Make (MyLogger) (MyFilter) (MySensor)
  > module SensorActions = struct
  >   type ctx = {
  >     mutable idx : int;
  >     readings : (int32 * int32) array;
  >     sensor : App.Sensor.t;
  >   }
  >   let sample ctx =
  >     let temp, pressure = ctx.readings.(ctx.idx) in
  >     ctx.idx <- (ctx.idx + 1) mod Array.length ctx.readings;
  >     App.Sensor.sample ctx.sensor temp pressure
  > end
  > module Fsm = SensorFsm.Make (SensorActions)
  > let () =
  >   let app = App.connect () in
  >   let ctx : SensorActions.ctx =
  >     { idx = 0;
  >       readings = [|
  >         (25l, 1013l);
  >         (150l, 1000l);
  >         (30l, 850l);
  >         (200l, 800l);
  >       |];
  >       sensor = app.sensor }
  >   in
  >   let fsm = Fsm.create ctx in
  >   let fsm = Fsm.step fsm SensorFsm.Tick in
  >   let fsm = Fsm.step fsm SensorFsm.Tick in
  >   let fsm = Fsm.step fsm SensorFsm.Tick in
  >   let fsm = Fsm.step fsm SensorFsm.Tick in
  >   let fsm = Fsm.step fsm SensorFsm.Shutdown in
  >   assert (Fsm.state fsm = SensorFsm.State SensorFsm.Off);
  >   assert (app.logger.count = 4);
  >   print_endline "pipeline: OK"
  > IMPL
  $ dune exec ./sm.exe 2>&1 && echo "pipeline_compile: OK"
  File "sm.ml", line 131, characters 4-21:
  131 |     App.Sensor.sample ctx.sensor temp pressure
            ^^^^^^^^^^^^^^^^^
  Error: Unbound value App.Sensor.sample
  [1]

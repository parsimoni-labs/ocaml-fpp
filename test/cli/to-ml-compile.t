Generated OCaml from state machines must compile and run correctly.

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

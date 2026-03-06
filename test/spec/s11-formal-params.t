FPP Spec §11 — Formal Parameters
=================================

§11.1 Value parameters

  $ cat > t.fpp <<EOF
  > port Simple(x: U32)
  > port Multi(x: U32, y: F64, name: string)
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§11.2 Ref parameters

  $ cat > t.fpp <<EOF
  > port WithRef(ref buf: string, size: U32)
  > port AllRef(ref a: U32, ref b: string)
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§11.3 Empty parameter list

  $ cat > t.fpp <<EOF
  > port NoParams
  > port EmptyParens()
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§11.4 Parameters with qualified types

  $ cat > t.fpp <<EOF
  > module Types { struct Data { value: F64 } }
  > port DataPort(data: Types.Data)
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§11.5 Parameters in commands and events

  $ cat > t.fpp <<EOF
  > module Fw { port Cmd port CmdResponse port CmdReg port Log port Time }
  > active component C {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   event port evOut
  >   time get port timeGet
  >   sync command SetConfig(name: string, value: U32)
  >   event Report(code: U32, msg: string) severity activity high format "{}: {}"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§11.6 Parameters in internal ports

  $ cat > t.fpp <<EOF
  > active component Worker {
  >   async input port dataIn: serial
  >   internal port process(data: U32, count: U32)
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

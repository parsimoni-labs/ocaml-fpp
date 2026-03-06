FPP Spec Syntax Tests
=====================

Tests modelled on the upstream FPP syntax test suite
(~/git/fpp/compiler/tools/fpp-syntax/test/syntax.fpp and state-machine.fpp).
Each section exercises a specific grammar production from the FPP specification
(https://nasa.github.io/fpp/fpp-spec.html).

Shared framework ports (required by special port specifiers)
  $ cat > fw.fpp <<EOF
  > module Fw {
  >   port Cmd
  >   port CmdResponse
  >   port CmdReg
  >   port Log
  >   port LogText
  >   port Time
  >   port Tlm
  >   port PrmGet
  >   port PrmSet
  >   port DpRequest
  >   port DpResponse
  >   port DpSend
  >   port DpGet
  > }
  > EOF

Definitions and Specifiers
--------------------------

Abstract type definition
  $ cat > t.fpp <<EOF
  > type T
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Type alias definition
  $ cat > t.fpp <<EOF
  > type TA = U32
  > type TB = F64
  > type TC = string
  > type TD = bool
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Array definition with default and format
  $ cat > t.fpp <<EOF
  > array A = [10] U32 default 0 format "{} counts"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

External state machine definition (bodyless)
  $ cat > t.fpp <<EOF
  > state machine SO
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Interface definition with general port, special port, and import
  $ cat > t.fpp <<EOF
  > port P
  > interface J { sync input port p: serial }
  > interface I {
  >   sync input port pI: [10] P priority 10 assert
  >   command recv port cmdIn
  >   import J
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Component definition (full upstream syntax.fpp example)
  $ cat > t.fpp <<EOF
  > port P
  > state machine SO
  > active component C {
  >   type T
  >   array A = [3] U32
  >   struct S { x: [3] U32, y: F32, z: string }
  >   enum E { X, Y, Z } default X
  > 
  >   product container Con id 0x00 default priority 10
  >   product record R: U32 array id 0x00
  > 
  >   async command Cmd(a: U32, b: F32) opcode 0x00 priority 10 assert
  > 
  >   external param P: U32 default 0 id 0x00 set opcode 0x01 save opcode 0x02
  > 
  >   async input port p1: [10] P priority 10 assert
  >   command recv port cmdIn
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   event port evOut
  >   time get port timeGet
  >   telemetry port tlmOut
  >   param get port prmGet
  >   param set port prmSet
  >   product request port productReq
  >   product send port productSend
  >   async product recv port productRecvIn priority 10 assert
  > 
  >   state machine SM
  >   state machine instance s1: SM priority 10 drop
  >   state machine instance s2: SM
  >   state machine instance so: SO
  > 
  >   output port p2: [10] P
  >   match p1 with p2
  > 
  >   telemetry Temp: U32 id 0x00 update on change format "{} s" \
  >     low { red 0, orange 1, yellow 2 } \
  >     high { yellow 10, orange 11, red 12 }
  > 
  >   event Ev(a: U32, b: F32) severity activity low id 0x00 format "{} {}" throttle 10
  > 
  >   internal port I(a: U32, b: F32) priority 10 assert
  > 
  >   import J
  > }
  > interface J { sync input port p: serial }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok


Component instance definition (simple)
  $ cat > t.fpp <<EOF
  > passive component C1 { }
  > instance c1: C1 base id 0x100
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Component instance definition (full)
  $ cat > t.fpp <<EOF
  > active component C2 { async input port cmdIn: serial }
  > constant CONSTRUCTION = 1
  > instance c2: C2 base id 0x200 type "T" at "C2.hpp" \
  >   queue size 100 stack size 1024 priority 10 cpu 0 {
  >   phase CONSTRUCTION "init()"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Constant definitions
  $ cat > t.fpp <<EOF
  > constant x = 0
  > constant y = 0xFF
  > constant z = -10
  > constant pi = 3.14159
  > constant flag = true
  > constant greeting = "hello"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Enum definition with explicit type and values
  $ cat > t.fpp <<EOF
  > enum E : I32 {
  >   X = 1
  >   Y = 2
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Enum with default
  $ cat > t.fpp <<EOF
  > enum Status { Ok, Error } default Ok
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Module definition with nested module
  $ cat > t.fpp <<EOF
  > module M {
  >   constant x = 0
  >   module Inner {
  >     constant y = 1
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Include specifier
  $ cat > t.fpp <<EOF
  > include "constant.fppi"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Port definition with params and return type
  $ cat > t.fpp <<EOF
  > port P(a: U32, b: F32) -> U32
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Port with ref parameter
  $ cat > t.fpp <<EOF
  > port P(ref buf: string)
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Struct definition with field formats
  $ cat > t.fpp <<EOF
  > struct S {
  >   x: U32 format "{} s"
  >   y: F32 format "{} m/s"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Struct with default values
  $ cat > t.fpp <<EOF
  > struct S {
  >   name: string,
  >   value: U32,
  >   enabled: bool
  > } default { name = "default", value = 0, enabled = false }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Location specifier
  $ cat > t.fpp <<EOF
  > passive component Sensor { }
  > locate component Sensor at "t.fpp"
  > type T
  > locate type T at "t.fpp"
  > instance s: Sensor base id 0x100
  > locate instance s at "t.fpp"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology Definition
-------------------

Topology with public and private instances
  $ cat > t.fpp <<EOF
  > passive component A { }
  > passive component B { }
  > instance i1: A base id 0x100
  > instance i2: B base id 0x200
  > topology T {
  >   instance i1
  >   private instance i2
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Direct connection graph with port indices and unmatched
  $ cat > t.fpp <<EOF
  > port P
  > passive component Src {
  >   output port p: [10] P
  >   output port p1: [2] P
  >   sync input port pIn: [2] P
  >   match pIn with p1
  > }
  > passive component Dst {
  >   sync input port p: [10] P
  >   sync input port p2: [2] P
  > }
  > instance i1: Src base id 0x100
  > instance i2: Dst base id 0x200
  > topology T {
  >   instance i1
  >   instance i2
  >   connections C {
  >     i1.p[0] -> i2.p[1]
  >     unmatched i1.p1[0] -> i2.p2[0]
  >     unmatched i1.p1[1] -> i2.p2[1]
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Graph pattern specifier with instance list
  $ cat > t.fpp <<EOF
  > active component Hub {
  >   async input port cmdIn: serial
  >   output port cmdReg: Fw.CmdReg
  >   output port cmdOut: Fw.Cmd
  >   async input port cmdResp: Fw.CmdResponse
  > }
  > active component M {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  > }
  > instance hub: Hub base id 0x001 queue size 10
  > instance m1: M base id 0x100 queue size 10
  > instance m2: M base id 0x200 queue size 10
  > topology T {
  >   instance hub
  >   instance m1
  >   instance m2
  >   command connections instance hub { m1, m2 }
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:19:11 │ <tu>.T │ input port 'm2.cmdIn' has no incoming connection  │
  │ ! │ t.fpp:18:11 │ <tu>.T │ input port 'm1.cmdIn' has no incoming connection  │
  │ ! │ t.fpp:17:11 │ <tu>.T │ input port 'hub.cmdResp' has no incoming          │
  │   │             │        │ connection                                        │
  │ ! │ t.fpp:17:11 │ <tu>.T │ input port 'hub.cmdIn' has no incoming connection │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Topology import
  $ cat > t.fpp <<EOF
  > passive component A { sync input port connect: serial }
  > passive component B {
  >   output port a: serial
  >   sync input port connect: serial
  > }
  > instance a: A base id 0x100
  > instance b: B base id 0x200
  > topology T1 {
  >   instance a
  >   instance b
  >   connections C { b.a -> a.connect }
  > }
  > topology T {
  >   import T1
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

All pattern graph types
  $ cat > t.fpp <<EOF
  > active component Managed {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   event port eventOut
  >   telemetry port tlmOut
  >   time get port timeGet
  >   text event port textEventOut
  > }
  > active component Hub {
  >   output port cmdReg: Fw.CmdReg
  >   output port cmdOut: Fw.Cmd
  >   async input port cmdResp: Fw.CmdResponse
  >   output port eventOut: Fw.Log
  >   output port tlmOut: Fw.Tlm
  >   output port timeOut: Fw.Time
  >   output port textOut: Fw.LogText
  > }
  > instance hub: Hub base id 0x001 queue size 10
  > instance mgd: Managed base id 0x100 queue size 10
  > topology T {
  >   instance hub
  >   instance mgd
  >   command connections instance hub
  >   event connections instance hub
  >   telemetry connections instance hub
  >   text event connections instance hub
  >   time connections instance hub
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:23:11 │ <tu>.T │ input port 'hub.cmdResp' has no incoming          │
  │   │             │        │ connection                                        │
  │ ! │ t.fpp:24:11 │ <tu>.T │ input port 'mgd.cmdIn' has no incoming connection │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Type Names
----------

All primitive type names and qualified identifiers
  $ cat > t.fpp <<EOF
  > array typeNameU32 = [10] U32
  > array typeNameF32 = [10] F32
  > array typeNameBool = [10] bool
  > array typeNameString = [10] string size 256
  > module a { module b { type c } }
  > array typeNameQID = [10] a.b.c
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Expressions
-----------

Arithmetic expressions
  $ cat > t.fpp <<EOF
  > constant arithExp = 1 + 2 * 3 - -4 * 5 + 6
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Array and struct expressions
  $ cat > t.fpp <<EOF
  > constant arrayExp = [ 1, 2, 3 ]
  > constant structExp = { a = 1, b = 2, c = 3 }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Boolean, FP, and string literal expressions
  $ cat > t.fpp <<EOF
  > constant boolExp = true
  > constant fpExp = 0.1234
  > constant intExp = 1234
  > constant identExp = boolExp
  > constant parenExp = (1 + 2) * 3
  > constant strExp = "This is a string."
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Dot expression (qualified identifier)
  $ cat > t.fpp <<EOF
  > module a { module b { constant c = 42 } }
  > constant dotExp = a.b.c
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Component Specifiers
--------------------

All command kinds (sync, async, guarded)
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   sync command SetRate(rate: U32) opcode 0x10
  >   async command Reset
  >   guarded command Configure(name: string, value: F64)
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

All event severities
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port cmdIn: serial
  >   event port evOut
  >   time get port timeGet
  >   event E1 severity activity high format "high"
  >   event E2 severity activity low format "low"
  >   event E3 severity warning high format "warn high"
  >   event E4 severity warning low format "warn low"
  >   event E5 severity fatal format "fatal"
  >   event E6 severity diagnostic format "diag"
  >   event E7(a: U32) severity activity high format "{}" throttle 10
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Event with throttle timeout (every clause)
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port cmdIn: serial
  >   event port evOut
  >   time get port timeGet
  >   event ET(a: U32) severity activity high id 0x00 format "{}" throttle 10 every {seconds=10}
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Telemetry with limits
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry T: U32 id 0x00 update on change format "{} s" \
  >     low { red 0, orange 1, yellow 2 } \
  >     high { yellow 10, orange 11, red 12 }
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Parameter specifiers (normal and external)
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port cmdIn: serial
  >   param get port prmGet
  >   param set port prmSet
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   param Threshold: F64 default 1.5
  >   param Name: string default "sensor"
  >   param MaxRetries: U32 default 3 id 0x200
  >   external param ExtP: U32 default 0 id 0x00 set opcode 0x01 save opcode 0x02
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Data products (container, record, request/recv/send/get ports)
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port cmdIn: serial
  >   product request port productReq
  >   async product recv port productRecv priority 10 assert
  >   product send port productSend
  >   sync product get port productGet
  >   product container Samples id 0x100 default priority 10
  >   product record Measurement: F64 id 0x200
  >   product record Batch: U32 array id 0x300
  > }
  > EOF
  $ ofpp check fw.fpp t.fpp
  ✓ fw.fpp
  ✓ t.fpp
  
  ✓ 2 files ok

Internal port specifier
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port cmdIn: serial
  >   internal port process(data: U32, count: U32) priority 5 assert
  >   internal port cleanup
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Port matching specifier
  $ cat > t.fpp <<EOF
  > port P
  > active component C {
  >   async input port pIn: [10] P
  >   output port pOut: [10] P
  >   match pIn with pOut
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Queue full behaviour (assert, drop, hook, block)
  $ cat > t.fpp <<EOF
  > active component C {
  >   async input port p1: serial priority 10 assert
  >   async input port p2: serial drop
  >   async input port p3: serial hook
  >   async input port p4: serial block
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Component with types, enums, structs, constants
  $ cat > t.fpp <<EOF
  > passive component C {
  >   enum Mode { Standby, Active, Error }
  >   struct Status { mode: Mode, uptime: U32 }
  >   constant MAX_SIZE = 256
  >   array Buf = [MAX_SIZE] U8
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Component with interface import
  $ cat > t.fpp <<EOF
  > module Net {
  >   interface S { sync input port connect: serial }
  > }
  > passive component Netif {
  >   import Net.S
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

All port directions and kinds
  $ cat > t.fpp <<EOF
  > port P
  > passive component C {
  >   sync input port p1: P
  >   guarded input port p2: serial
  >   output port p3: serial
  >   output port p4: [4] serial
  > }
  > active component D {
  >   async input port p1: serial
  > }
  > queued component E {
  >   async input port p1: serial
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Annotations
-----------

Pre-annotations and post-annotations
  $ cat > t.fpp <<EOF
  > @ This is a pre-annotation
  > constant x = 42
  > constant y = 0 @< This is a post-annotation
  > @ First line
  > @ Second line
  > enum Color { Red, Green, Blue }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

State Machine (upstream state-machine.fpp)
------------------------------------------

State machine with types, actions, guards, and signals
  $ cat > t.fpp <<EOF
  > state machine M {
  >   array A = [3] U32
  >   constant c = 0
  >   enum E { X, Y, Z } default X
  >   struct S { x: [3] U32, y: F32, z: string }
  >   type T
  >   type X = U32
  > 
  >   action a1
  >   action a2
  >   action a3
  >   action a4: U32
  > 
  >   guard g1
  >   guard g2: U32
  > 
  >   signal s1: U32
  >   signal s2
  >   signal s3
  > 
  >   state S1
  >   initial enter S1
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬────────────┬────┬────────────────────────────────────────────────────────╮
  │   │ Location   │ SM │ Warning                                                │
  ├───┼────────────┼────┼────────────────────────────────────────────────────────┤
  │ ! │ t.fpp:21:8 │ M  │ signal 's1' not handled in state 'S1'                  │
  │ ! │ t.fpp:21:8 │ M  │ signal 's2' not handled in state 'S1'                  │
  │ ! │ t.fpp:21:8 │ M  │ signal 's3' not handled in state 'S1'                  │
  │ ! │ t.fpp:12:9 │ M  │ unused action 'a4'                                     │
  │ ! │ t.fpp:11:9 │ M  │ unused action 'a3'                                     │
  │ ! │ t.fpp:10:9 │ M  │ unused action 'a2'                                     │
  │ ! │ t.fpp:9:9  │ M  │ unused action 'a1'                                     │
  │ ! │ t.fpp:15:8 │ M  │ unused guard 'g2'                                      │
  │ ! │ t.fpp:14:8 │ M  │ unused guard 'g1'                                      │
  │ ! │ t.fpp:19:9 │ M  │ unused signal 's3'                                     │
  │ ! │ t.fpp:18:9 │ M  │ unused signal 's2'                                     │
  │ ! │ t.fpp:17:9 │ M  │ unused signal 's1'                                     │
  │ ! │ t.fpp:21:8 │ M  │ state 'S1' has no outgoing transitions (potential      │
  │   │            │    │ deadlock)                                              │
  ╰───┴────────────┴────┴────────────────────────────────────────────────────────╯
  
  ✓ t.fpp

Initial transition with do-actions
  $ cat > t.fpp <<EOF
  > state machine M {
  >   action a1
  >   state S1
  >   choice C { if g1 enter S1 else enter S1 }
  >   guard g1
  >   initial do { a1 } enter C
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Choice with guards and actions
  $ cat > t.fpp <<EOF
  > state machine M {
  >   action a1
  >   action a2
  >   action a3
  >   guard g1
  >   signal s1
  >   state S1 { on s1 enter C }
  >   state S2 {
  >     state S3
  >     initial enter S3
  >   }
  >   choice C { if g1 do { a1, a2 } enter S1 else do { a2, a3 } enter S2 }
  >   initial enter S1
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬────────────┬────┬────────────────────────────────────────────────────────╮
  │   │ Location   │ SM │ Warning                                                │
  ├───┼────────────┼────┼────────────────────────────────────────────────────────┤
  │ ! │ t.fpp:9:10 │ M  │ signal 's1' not handled in state 'S3'                  │
  │ ! │ t.fpp:9:10 │ M  │ state 'S3' has no outgoing transitions (potential      │
  │   │            │    │ deadlock)                                              │
  ╰───┴────────────┴────┴────────────────────────────────────────────────────────╯
  
  ✓ t.fpp

States with entry/exit actions
  $ cat > t.fpp <<EOF
  > state machine M {
  >   action a1
  >   action a2
  >   signal s1
  >   signal s2
  >   guard g1
  >   state S2 {
  >     entry do { a1, a2 }
  >     exit do { a1, a2 }
  >     state S3
  >     initial do { a1, a2 } enter S3
  >     on s1 if g1 do { a1 } enter S3
  >     on s2 do { a1 }
  >   }
  >   initial do { a1 } enter S2
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Transitions: enter, do+enter, do-only (internal), guarded
  $ cat > t.fpp <<EOF
  > state machine M {
  >   signal s1
  >   signal s2
  >   signal s3
  >   signal s4
  >   signal s5
  >   signal s6
  >   action a1
  >   guard g1
  >   state S1 {
  >     on s1 if g1 do { a1 } enter S1
  >     on s2 if g1 enter S1
  >     on s3 if g1 enter S1
  >     on s4 enter S1
  >     on s5 if g1 do { a1 }
  >     on s6 do { a1 }
  >   }
  >   initial enter S1
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Empty do block (spec allows zero actions)
  $ cat > t.fpp <<EOF
  > state machine M {
  >   signal s1
  >   action a1
  >   state S1 { on s1 do { } }
  >   initial do { } enter S1
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:3:9: warning in SM 'M': unused action 'a1'
  ✓ t.fpp

State machine instance in component
  $ cat > t.fpp <<EOF
  > state machine Counter {
  >   signal Tick
  >   action count
  >   state Counting { on Tick do count }
  >   initial enter Counting
  > }
  > active component Timed {
  >   state machine instance counter: Counter priority 5 assert
  >   state machine instance counter2: Counter
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Simple door state machine (two-state cycle)
  $ cat > t.fpp <<EOF
  > state machine Door {
  >   signal Open
  >   signal Close
  >   state Closed { on Open enter Opened }
  >   state Opened { on Close enter Closed }
  >   initial enter Closed
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬───────────┬──────┬───────────────────────────────────────────────────────╮
  │   │ Location  │ SM   │ Warning                                               │
  ├───┼───────────┼──────┼───────────────────────────────────────────────────────┤
  │ ! │ t.fpp:4:8 │ Door │ signal 'Close' not handled in state 'Closed'          │
  │ ! │ t.fpp:5:8 │ Door │ signal 'Open' not handled in state 'Opened'           │
  │ ! │ t.fpp:4:8 │ Door │ states {'Closed', 'Opened'} form a cycle with no exit │
  ╰───┴───────────┴──────┴───────────────────────────────────────────────────────╯
  
  ✓ t.fpp

Nested states with initial transitions
  $ cat > t.fpp <<EOF
  > state machine Nested {
  >   signal A
  >   signal B
  >   state Outer {
  >     state Inner1 { on A enter Inner2 }
  >     state Inner2 { on B enter Inner1 }
  >     initial enter Inner1
  >   }
  >   initial enter Outer
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬────────────┬────────┬──────────────────────────────────────────╮
  │   │ Location   │ SM     │ Warning                                  │
  ├───┼────────────┼────────┼──────────────────────────────────────────┤
  │ ! │ t.fpp:5:10 │ Nested │ signal 'B' not handled in state 'Inner1' │
  │ ! │ t.fpp:6:10 │ Nested │ signal 'A' not handled in state 'Inner2' │
  ╰───┴────────────┴────────┴──────────────────────────────────────────╯
  
  ✓ t.fpp

Combined Example
----------------

Full system (components, instances, state machines, topologies)
  $ cat > t.fpp <<EOF
  > constant MAX_SENSORS = 4
  > enum SensorType { Temperature, Pressure, Humidity }
  > struct SensorData { value: F64, sensor_type: SensorType }
  > array SensorArray = [MAX_SENSORS] SensorData
  > port SensorPort(data: SensorData)
  > port StatusPort -> bool
  > module Sensors {
  >   interface S { sync input port connect: serial }
  >   passive component Reader {
  >     import Sensors.S
  >     output port data: SensorPort
  >   }
  > }
  > passive component Aggregator {
  >   sync input port dataIn: [MAX_SENSORS] SensorPort
  >   output port status: StatusPort
  >   sync input port start: serial
  > }
  > state machine SensorMonitor {
  >   signal DataReady
  >   signal Timeout
  >   action processData
  >   state Waiting { on DataReady do processData enter Processing }
  >   state Processing { on Timeout enter Waiting }
  >   initial enter Waiting
  > }
  > instance reader: Sensors.Reader base id 0x100
  > instance aggregator: Aggregator base id 0x200
  > topology SensorSystem {
  >   instance reader
  >   instance aggregator
  >   connections Data {
  >     reader.data -> aggregator.dataIn
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬───────────────────┬────────────────────────────────────────╮
  │   │ Location    │ SM                │ Warning                                │
  ├───┼─────────────┼───────────────────┼────────────────────────────────────────┤
  │ ! │ t.fpp:31:11 │ <tu>.SensorSystem │ input port 'aggregator.start' has no   │
  │   │             │                   │ incoming connection                    │
  │ ! │ t.fpp:23:8  │ SensorMonitor     │ signal 'Timeout' not handled in state  │
  │   │             │                   │ 'Waiting'                              │
  │ ! │ t.fpp:24:8  │ SensorMonitor     │ signal 'DataReady' not handled in      │
  │   │             │                   │ state 'Processing'                     │
  │ ! │ t.fpp:24:8  │ SensorMonitor     │ states {'Processing', 'Waiting'} form  │
  │   │             │                   │ a cycle with no exit                   │
  ╰───┴─────────────┴───────────────────┴────────────────────────────────────────╯
  
  ✓ t.fpp

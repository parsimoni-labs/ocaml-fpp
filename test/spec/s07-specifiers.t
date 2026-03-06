FPP Spec §7 — Specifiers
========================

§7.1 Command specifiers — all kinds

  $ cat > t.fpp <<EOF
  > module Fw { port Cmd port CmdResponse port CmdReg }
  > active component Cmds {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   sync command SyncCmd
  >   async command AsyncCmd
  >   guarded command GuardedCmd
  >   sync command WithParams(name: string, value: U32)
  >   async command WithOpcode opcode 0x10
  >   async command WithPriority priority 5
  >   async command WithQueueFull drop
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.2 Container specifiers

  $ cat > t.fpp <<EOF
  > module Fw { port DpRequest port DpResponse port DpSend }
  > active component DpComp {
  >   async input port cmdIn: serial
  >   product request port productReq
  >   async product recv port productRecv
  >   product send port productSend
  >   product container Samples
  >   product container WithId id 0x100
  >   product container WithPri id 0x200 default priority 10
  >   product record Data: U32 id 0x300
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.3 Event specifiers — all severities

  $ cat > t.fpp <<EOF
  > module Fw { port Log port Time }
  > active component Events {
  >   async input port cmdIn: serial
  >   event port evOut
  >   time get port timeGet
  >   event E1 severity fatal format "fatal"
  >   event E2 severity warning high format "warn high"
  >   event E3 severity warning low format "warn low"
  >   event E4 severity command format "cmd"
  >   event E5 severity activity high format "act high"
  >   event E6 severity activity low format "act low"
  >   event E7 severity diagnostic format "diag"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.3 Event with params, id, and throttle

  $ cat > t.fpp <<EOF
  > module Fw { port Log port Time }
  > active component EventDetail {
  >   async input port cmdIn: serial
  >   event port evOut
  >   time get port timeGet
  >   event Error(code: U32, msg: string) severity warning high \
  >     id 0x100 format "Error {}: {}"
  >   event Flood severity activity high format "flood" throttle 10
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.3 Event throttle with every (timeout)

  $ cat > t.fpp <<EOF
  > module Fw { port Log port Time }
  > active component EventThrottle {
  >   async input port cmdIn: serial
  >   event port evOut
  >   time get port timeGet
  >   event Flood severity activity high format "flood" throttle 10 every 60
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.4 Include specifiers — in component

  $ cat > inc.fpp <<EOF
  > EOF
  $ cat > t.fpp <<EOF
  > passive component C { include "inc.fpp" }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.4 Include specifiers — in module

  $ cat > inc.fpp <<EOF
  > constant INCLUDED = 1
  > EOF
  $ cat > t.fpp <<EOF
  > module M { include "inc.fpp" }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.4 Include specifiers — in topology

  $ cat > inc.fpp <<EOF
  > EOF
  $ cat > t.fpp <<EOF
  > topology T { include "inc.fpp" }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.5 Internal port specifiers

  $ cat > t.fpp <<EOF
  > active component Worker {
  >   async input port dataIn: serial
  >   internal port process(data: U32, count: U32) priority 5
  >   internal port cleanup
  >   internal port heavy drop
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.7 Parameter specifiers

  $ cat > t.fpp <<EOF
  > module Fw {
  >   port Cmd port CmdResponse port CmdReg
  >   port PrmGet port PrmSet
  > }
  > active component Params {
  >   async input port cmdIn: serial
  >   param get port prmGet
  >   param set port prmSet
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   param Threshold: F64 default 1.5
  >   param Name: string default "sensor"
  >   param MaxRetries: U32 default 3 id 0x200
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.7 External parameter

  $ cat > t.fpp <<EOF
  > module Fw {
  >   port Cmd port CmdResponse port CmdReg
  >   port PrmGet port PrmSet
  > }
  > active component ExtParams {
  >   async input port cmdIn: serial
  >   param get port prmGet
  >   param set port prmSet
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   external param Calibration: F64 default 1.0
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.7 Parameter with set opcode and save opcode

  $ cat > t.fpp <<EOF
  > module Fw {
  >   port Cmd port CmdResponse port CmdReg
  >   port PrmGet port PrmSet
  > }
  > active component OpcodeParams {
  >   async input port cmdIn: serial
  >   param get port prmGet
  >   param set port prmSet
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   param Rate: U32 default 50 id 0x10 set opcode 0x20 save opcode 0x21
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.8 Port instance specifiers — general ports

  $ cat > t.fpp <<EOF
  > port Ping
  > passive component Ports {
  >   sync input port syncIn: serial
  >   guarded input port guardedIn: serial
  >   output port out: serial
  > }
  > active component AsyncPorts {
  >   async input port asyncIn: serial
  >   async input port withPri: serial priority 5
  >   async input port withDrop: serial drop
  >   async input port withAssert: serial assert
  >   async input port withBlock: serial block
  >   async input port withHook: serial hook
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.8 Port instance specifiers — sized (array) ports

  $ cat > t.fpp <<EOF
  > active component Hub {
  >   async input port dataIn: [10] serial
  >   output port dataOut: [10] serial
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.8 Port instance specifiers — special ports (all kinds)

  $ cat > t.fpp <<EOF
  > module Fw {
  >   port Cmd port CmdResponse port CmdReg
  >   port Log port LogText port Time port Tlm
  >   port PrmGet port PrmSet
  >   port DpRequest port DpResponse port DpSend port DpGet
  > }
  > active component AllSpecial {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   event port eventOut
  >   text event port textEventOut
  >   time get port timeGet
  >   telemetry port tlmOut
  >   param get port prmGet
  >   param set port prmSet
  >   product request port productReq
  >   async product recv port productRecv
  >   product send port productSend
  >   product get port productGet
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.8 Special port with input kind prefix (only product recv allows it per spec)

  $ cat > t.fpp <<EOF
  > module Fw { port DpResponse }
  > active component SpecialPrefix {
  >   async input port cmdIn: serial
  >   async product recv port dpRecv priority 5
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.8 Product get port does NOT allow input kind prefix

  $ cat > t.fpp <<EOF
  > module Fw { port DpGet }
  > passive component Bad {
  >   sync product get port dpGet
  > }
  > EOF
  $ ofpp check t.fpp
  ✗ t.fpp:3:24: error in SM '<tu>.Bad': input kind not allowed on product get port
  
  ✗ 1/1 file failed
  [1]


§7.9 Port matching specifiers

  $ cat > t.fpp <<EOF
  > port Ping
  > active component PingPong {
  >   async input port pingIn: Ping
  >   output port pingOut: Ping
  >   match pingIn with pingOut
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.10 Record specifiers

  $ cat > t.fpp <<EOF
  > module Fw { port DpRequest port DpResponse port DpSend }
  > active component Records {
  >   async input port cmdIn: serial
  >   product request port productReq
  >   async product recv port productRecv
  >   product send port productSend
  >   product container C id 0x100
  >   product record Scalar: F64 id 0x200
  >   product record Array: U32 array id 0x300
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.13 Telemetry channel specifiers

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > active component Tlm {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry Temp: F64
  >   telemetry WithId: U32 id 0x100
  >   telemetry OnChange: F64 update on change
  >   telemetry Always: U32 update always
  >   telemetry Formatted: U32 format "{}"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.13 Telemetry with limits

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > active component TlmLimits {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry Temperature: F64 \
  >     low { red -40, orange -20, yellow 0 } \
  >     high { yellow 50, orange 70, red 100 }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§7.14 Location specifiers — all kinds

  $ cat > t.fpp <<EOF
  > passive component Comp { }
  > instance inst: Comp base id 0x100
  > constant MAX = 10
  > port Ping
  > interface Iface { sync input port connect: serial }
  > state machine Sm {
  >   signal Go
  >   state Idle { on Go enter Idle }
  >   initial enter Idle
  > }
  > topology Top { }
  > type T
  > dictionary type DT
  > locate component Comp at "t.fpp"
  > locate instance inst at "t.fpp"
  > locate constant MAX at "t.fpp"
  > locate port Ping at "t.fpp"
  > locate interface Iface at "t.fpp"
  > locate state machine Sm at "t.fpp"
  > locate topology Top at "t.fpp"
  > locate type T at "t.fpp"
  > locate dictionary type DT at "t.fpp"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

FPP Spec §5.14 — Topology Definitions
======================================

Empty topology

  $ cat > t.fpp <<EOF
  > topology Empty { }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology with instances (public by default)

  $ cat > t.fpp <<EOF
  > passive component A { }
  > instance a: A base id 0x100
  > topology T { instance a }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology with explicit public keyword

  $ cat > t.fpp <<EOF
  > passive component A { }
  > instance a: A base id 0x100
  > topology T { public instance a }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology with private instances

  $ cat > t.fpp <<EOF
  > passive component A { }
  > passive component B { }
  > instance a: A base id 0x100
  > instance b: B base id 0x200
  > topology T {
  >   instance a
  >   private instance b
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology with direct connections

  $ cat > t.fpp <<EOF
  > passive component Src { output port out: serial }
  > passive component Dst { sync input port dataIn: serial }
  > instance src: Src base id 0x100
  > instance dst: Dst base id 0x200
  > topology T {
  >   instance src
  >   instance dst
  >   connections Data { src.out -> dst.dataIn }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology with indexed connections

  $ cat > t.fpp <<EOF
  > passive component Src { output port out: [4] serial }
  > passive component Dst { sync input port work: serial }
  > instance src: Src base id 0x100
  > instance d0: Dst base id 0x200
  > instance d1: Dst base id 0x300
  > topology T {
  >   instance src
  >   instance d0
  >   instance d1
  >   connections Dispatch {
  >     src.out[0] -> d0.work
  >     src.out[1] -> d1.work
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology with unmatched connection

  $ cat > t.fpp <<EOF
  > port Ping
  > passive component Src {
  >   output port out: Ping
  >   sync input port pingIn: Ping
  >   match pingIn with out
  > }
  > passive component Dst { sync input port dataIn: Ping }
  > instance src: Src base id 0x100
  > instance dst: Dst base id 0x200
  > topology T {
  >   instance src
  >   instance dst
  >   connections Data { unmatched src.out -> dst.dataIn }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Topology import

  $ cat > t.fpp <<EOF
  > passive component A { sync input port connect: serial }
  > passive component B {
  >   output port a: serial
  >   sync input port connect: serial
  > }
  > instance a: A base id 0x100
  > instance b: B base id 0x200
  > topology Sub {
  >   instance a
  >   instance b
  >   connections Wire { b.a -> a.connect }
  > }
  > topology Main { import Sub }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

Pattern graph — all 7 kinds (syntax acceptance)

  $ cat > t.fpp <<EOF
  > passive component A { }
  > instance a: A base id 0x100
  > topology T1 { instance a command connections instance a }
  > topology T2 { instance a event connections instance a }
  > topology T3 { instance a health connections instance a }
  > topology T4 { instance a param connections instance a }
  > topology T5 { instance a telemetry connections instance a }
  > topology T6 { instance a text event connections instance a }
  > topology T7 { instance a time connections instance a }
  > EOF
  $ ofpp check t.fpp
  ✗ t.fpp:3:54: error in SM '<tu>.T1': command pattern source has no Fw.CmdReg port
  ✗ t.fpp:3:54: error in SM '<tu>.T1': command pattern source has no Fw.Cmd port
  ✗ t.fpp:3:54: error in SM '<tu>.T1': command pattern source has no Fw.CmdResponse port
  ✗ t.fpp:4:52: error in SM '<tu>.T2': event pattern source has no Fw.Log port
  ✗ t.fpp:5:53: error in SM '<tu>.T3': health pattern source has no Svc.Ping input port
  ✗ t.fpp:6:52: error in SM '<tu>.T4': param pattern source has no Fw.PrmGet port
  ✗ t.fpp:6:52: error in SM '<tu>.T4': param pattern source has no Fw.PrmSet port
  ✗ t.fpp:7:56: error in SM '<tu>.T5': telemetry pattern source has no Fw.Tlm port
  ✗ t.fpp:8:57: error in SM '<tu>.T6': text event pattern source has no Fw.LogText port
  ✗ t.fpp:9:51: error in SM '<tu>.T7': time pattern source has no Fw.Time port
  
  ✗ 1/1 file failed
  [1]


Pattern graph with explicit target list

  $ cat > t.fpp <<EOF
  > passive component A { }
  > instance a: A base id 0x100
  > instance b: A base id 0x200
  > topology T {
  >   instance a
  >   instance b
  >   time connections instance a { b }
  > }
  > EOF
  $ ofpp check t.fpp
  ✗ t.fpp:7:28: error in SM '<tu>.T': time pattern source has no Fw.Time port
  ✗ t.fpp:7:32: error in SM '<tu>.T': time pattern target has no time get port
  
  ✗ 1/1 file failed
  [1]


Telemetry packet sets

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > active component S {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry Temp: F64
  >   telemetry Pressure: F64
  >   telemetry Humidity: F64
  > }
  > instance s: S base id 0x100 queue size 10
  > topology T {
  >   instance s
  >   telemetry packets SensorPkts {
  >     packet Env id 1 group 0 {
  >       s.Temp
  >       s.Pressure
  >     }
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:12:11: warning in SM '<tu>.T': input port 's.cmdIn' has no incoming connection
  ✗ t.fpp:12:11: error in SM '<tu>.T': channel 's.Humidity' is neither used nor omitted
  
  ✗ 1/1 file failed
  [1]


Telemetry packet sets with omit

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > active component S {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry A: U32
  >   telemetry B: U32
  >   telemetry C: U32
  > }
  > instance s: S base id 0x100 queue size 10
  > topology T {
  >   instance s
  >   telemetry packets Pkts {
  >     packet Main { s.A s.B }
  >   } omit { s.C }
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:12:11: warning in SM '<tu>.T': input port 's.cmdIn' has no incoming connection
  ✓ t.fpp

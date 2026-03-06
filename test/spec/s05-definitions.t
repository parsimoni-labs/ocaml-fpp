FPP Spec §5 — Definitions
=========================

§5.1 Abstract type definitions

  $ cat > t.fpp <<EOF
  > type Timestamp
  > type ExternalData
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.2 Alias type definitions

  $ cat > t.fpp <<EOF
  > type Counter = U32
  > type Voltage = F64
  > type Name = string
  > type Flag = bool
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.2 Alias with string size

  $ cat > t.fpp <<EOF
  > type ShortName = string size 32
  > type LongName = string size 256
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.3 Array definitions — basic, with default, with format

  $ cat > t.fpp <<EOF
  > array Coefficients = [4] F64
  > array Thresholds = [3] U32 default [10, 20, 30]
  > array Voltages = [4] F64 format "{.2f}"
  > array Flags = [3] U8 default [0, 0, 0] format "{}"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.4 Component definitions — all three kinds

  $ cat > t.fpp <<EOF
  > passive component Sensor { }
  > active component Controller {
  >   async input port cmdIn: serial
  > }
  > queued component Handler {
  >   async input port dataIn: serial
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.4 Component with type defs inside

  $ cat > t.fpp <<EOF
  > passive component Typed {
  >   type Opaque
  >   type Alias = U32
  >   enum Mode { Standby, Active, Error }
  >   struct Status { mode: Mode, uptime: U32 }
  >   array Readings = [4] F64
  >   constant MAX_SIZE = 256
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.5 Component instance definitions — all optional fields

  $ cat > t.fpp <<EOF
  > passive component Led { }
  > instance led: Led base id 0x100
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.5 Instance with type string

  $ cat > t.fpp <<EOF
  > passive component Sensor { }
  > instance sensor: Sensor base id 0x100 \
  >   type "Sensors::TemperatureSensor"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.5 Instance with at file path

  $ cat > t.fpp <<EOF
  > passive component Driver { }
  > instance driver: Driver base id 0x100 \
  >   at "Components/Driver/Driver.cpp"
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.5 Instance with all optional fields

  $ cat > t.fpp <<EOF
  > active component Worker { async input port work: serial }
  > instance worker: Worker base id 0x100 \
  >   type "WorkerImpl" \
  >   at "Components/Worker.cpp" \
  >   queue size 20 \
  >   stack size 4096 \
  >   priority 10 \
  >   cpu 0 {
  >   phase 1 "worker.init()"
  >   phase 2 "worker.start()"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.5 Instance with qualified component

  $ cat > t.fpp <<EOF
  > module Sensors {
  >   passive component Temperature { }
  > }
  > instance temp: Sensors.Temperature base id 0x200
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.6 Constant definitions

  $ cat > t.fpp <<EOF
  > constant a = 0
  > constant b = 1.0
  > constant c = "hello"
  > constant d = true
  > constant e = a
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.7 Enum definitions — inferred type, explicit type, with default

  $ cat > t.fpp <<EOF
  > enum Color { Red, Green, Blue }
  > enum Priority : U8 { Low = 0, Medium = 1, High = 2 }
  > enum Status { Ok, Error } default Ok
  > enum Direction { North, South, East, West }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.8 Enumerated constant definitions — with and without values

  $ cat > t.fpp <<EOF
  > enum AutoIncr { A, B, C }
  > enum Explicit { None = 0, Timeout = 1, Overflow = 2, Fatal = 100 }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.9 Module definitions — nesting, scoping

  $ cat > t.fpp <<EOF
  > module Outer {
  >   constant X = 1
  >   module Inner {
  >     constant Y = 2
  >     passive component Device { }
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.9 Module with all member kinds

  $ cat > t.fpp <<EOF
  > module M {
  >   type Opaque
  >   type Alias = U32
  >   constant C = 42
  >   enum E { A, B }
  >   struct S { x: U32 }
  >   array Arr = [2] U32
  >   port Ping
  >   interface I { sync input port connect: serial }
  >   state machine Sm {
  >     signal Go
  >     state Idle { on Go enter Idle }
  >     initial enter Idle
  >   }
  >   passive component Comp { }
  >   instance comp: Comp base id 0x100
  >   topology T { instance comp }
  >   locate component Comp at "t.fpp"
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.10 Port definitions — all forms

  $ cat > t.fpp <<EOF
  > port Ping
  > port DataSend(data: string, size: U32)
  > port GetValue(key: string) -> U32
  > port IsReady -> bool
  > port BufferSend(ref buf: string)
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.11 Port interface definitions

  $ cat > t.fpp <<EOF
  > interface Connectable {
  >   sync input port connect: serial
  > }
  > port Ping
  > interface Device {
  >   sync input port connect: serial
  >   sync input port ping: Ping
  >   output port status: serial
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.11 Interface with import (interface extending interface)

  $ cat > t.fpp <<EOF
  > interface Base {
  >   sync input port connect: serial
  > }
  > interface Extended {
  >   import Base
  >   output port status: serial
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.11 Interface inside module

  $ cat > t.fpp <<EOF
  > module Ethernet {
  >   interface S {
  >     sync input port connect: serial
  >   }
  >   passive component Make {
  >     import Ethernet.S
  >     output port net: serial
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.11 Nested module interfaces

  $ cat > t.fpp <<EOF
  > module Tcpip {
  >   module Ip {
  >     interface S { sync input port connect: serial }
  >   }
  >   module Tcp {
  >     interface S { sync input port connect: serial }
  >   }
  > }
  > passive component Router { import Tcpip.Ip.S }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.13 Struct definitions — basic, with default, member array, member format

  $ cat > t.fpp <<EOF
  > struct Point { x: F64, y: F64 }
  > struct Config {
  >   name: string,
  >   value: U32,
  >   enabled: bool
  > } default { name = "default", value = 0, enabled = false }
  > struct Buffer { data: [256] U8, len: U32 }
  > struct Measurement { value: F64 format "{.3f}", label: string }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Topology definitions — see s05-topology.t

§5.16 Dictionary definitions

  $ cat > t.fpp <<EOF
  > dictionary type Status
  > dictionary type Counter = U32
  > dictionary constant DefaultTimeout = 1000
  > dictionary enum OpState { Init, Ready, Active }
  > dictionary struct Info { name: string, version: U32 }
  > dictionary array Samples = [10] F64
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

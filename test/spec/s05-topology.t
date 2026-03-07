FPP Spec §5.14 — Topology Definitions
======================================

Empty topology

  $ cat > t.fpp <<EOF
  > topology Empty { }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Component instance specifiers — public and private (§7.2)

  $ cat > t.fpp <<EOF
  > passive component A { }
  > passive component B { }
  > passive component C { }
  > instance a: A base id 0x100
  > instance b: B base id 0x200
  > instance c: C base id 0x300
  > topology T {
  >   instance a
  >   instance b
  >   private instance c
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Direct connection graph (§7.3)

  $ cat > t.fpp <<EOF
  > passive component Src { output port p1: serial }
  > passive component Dst { sync input port p: serial }
  > instance a: Src base id 0x100
  > instance c: Dst base id 0x200
  > instance d: Dst base id 0x300
  > topology T {
  >   instance a
  >   instance c
  >   instance d
  >   connections C1 { a.p1 -> c.p }
  >   connections C1 { a.p1 -> d.p }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Indexed connections

  $ cat > t.fpp <<EOF
  > passive component Src { output port p1: [4] serial }
  > passive component Dst { sync input port p: serial }
  > instance a: Src base id 0x100
  > instance c: Dst base id 0x200
  > instance d: Dst base id 0x300
  > topology T {
  >   instance a
  >   instance c
  >   instance d
  >   connections C1 {
  >     a.p1[0] -> c.p
  >     a.p1[1] -> d.p
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Unmatched connections

  $ cat > t.fpp <<EOF
  > port Ping
  > passive component A {
  >   output port out: Ping
  >   sync input port pingIn: Ping
  >   match pingIn with out
  > }
  > passive component B { sync input port dataIn: Ping }
  > instance a: A base id 0x100
  > instance b: B base id 0x200
  > topology T {
  >   instance a
  >   instance b
  >   connections Data { unmatched a.out -> b.dataIn }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Topology import — from spec §7.12 example

  $ cat > t.fpp <<EOF
  > passive component CompA {
  >   output port p1: [4] serial
  >   output port p2: serial
  >   output port p3: serial
  > }
  > passive component CompB { output port p: serial }
  > passive component CompC { sync input port p: serial }
  > instance a: CompA base id 0x100
  > instance b: CompB base id 0x200
  > instance c: CompC base id 0x300
  > instance d: CompC base id 0x400
  > instance e: CompC base id 0x500
  > instance f: CompC base id 0x600
  > topology A {
  >   instance a
  >   private instance b
  >   instance c
  >   connections C1 { a.p1 -> c.p }
  >   connections C2 { b.p -> c.p }
  > }
  > topology B {
  >   import A
  >   instance d
  >   instance e
  >   instance f
  >   connections C1 { a.p1 -> d.p }
  >   connections C2 { a.p2 -> e.p }
  >   connections C3 { a.p3 -> f.p }
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Pattern graph — command connections (§7.3)

  $ cat > t.fpp <<EOF
  > module Fw {
  >   port Cmd
  >   port CmdResponse
  >   port CmdReg
  > }
  > passive component CommandDispatcher {
  >   output port cmdOut: [20] Fw.Cmd
  >   sync input port cmdRegIn: [20] Fw.CmdReg
  >   sync input port cmdRespIn: Fw.CmdResponse
  > }
  > active component CommandSequencer {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  > }
  > active component EventLogger {
  >   async input port cmdIn: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  > }
  > instance commandDispatcher: CommandDispatcher base id 0x100
  > instance commandSequencer: CommandSequencer base id 0x200 \
  >   queue size 10
  > instance eventLogger: EventLogger base id 0x300 \
  >   queue size 10
  > topology T {
  >   instance commandDispatcher
  >   instance commandSequencer
  >   instance eventLogger
  >   command connections instance commandDispatcher
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:28:11 │ <tu>.T │ input port 'commandSequencer.cmdIn' has no        │
  │   │             │        │ incoming connection                               │
  │ ! │ t.fpp:27:11 │ <tu>.T │ input port 'commandDispatcher.cmdRespIn' has no   │
  │   │             │        │ incoming connection                               │
  │ ! │ t.fpp:27:11 │ <tu>.T │ input port 'commandDispatcher.cmdRegIn' has no    │
  │   │             │        │ incoming connection                               │
  │ ! │ t.fpp:29:11 │ <tu>.T │ input port 'eventLogger.cmdIn' has no incoming    │
  │   │             │        │ connection                                        │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 Pattern graph — event connections (§7.3)

  $ cat > t.fpp <<EOF
  > module Fw { port Log port Time }
  > passive component EventLogger {
  >   sync input port logIn: Fw.Log
  > }
  > active component Sensor {
  >   async input port cmdIn: serial
  >   event port eventOut
  >   time get port timeGet
  >   event Overtemp severity warning high format "overtemp"
  > }
  > instance eventLogger: EventLogger base id 0x100
  > instance sensor: Sensor base id 0x200 queue size 10
  > topology T {
  >   instance eventLogger
  >   instance sensor
  >   event connections instance eventLogger
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:15:11 │ <tu>.T │ input port 'sensor.cmdIn' has no incoming         │
  │   │             │        │ connection                                        │
  │ ! │ t.fpp:14:11 │ <tu>.T │ input port 'eventLogger.logIn' has no incoming    │
  │   │             │        │ connection                                        │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 Pattern graph — health connections (§7.3)

  $ cat > t.fpp <<EOF
  > module Svc { port Ping }
  > active component HealthMonitor {
  >   async input port pingIn: [10] Svc.Ping
  >   output port pingOut: [10] Svc.Ping
  > }
  > active component Sensor {
  >   async input port pingIn: Svc.Ping
  >   output port pingOut: Svc.Ping
  > }
  > instance hlth: HealthMonitor base id 0x100 queue size 10
  > instance sensor: Sensor base id 0x200 queue size 10
  > topology T {
  >   instance hlth
  >   instance sensor
  >   health connections instance hlth
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:14:11: warning in SM '<tu>.T': input port 'sensor.pingIn' has no incoming connection
  ✓ t.fpp

§5.14 Pattern graph — param connections (§7.3)

  $ cat > t.fpp <<EOF
  > module Fw {
  >   port Cmd port CmdResponse port CmdReg
  >   port PrmGet port PrmSet
  > }
  > passive component ParamDb {
  >   output port prmGetOut: Fw.PrmGet
  >   sync input port prmSetIn: Fw.PrmSet
  > }
  > active component Sensor {
  >   async input port cmdIn: serial
  >   param get port prmGet
  >   param set port prmSet
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   param Threshold: F64 default 1.5
  > }
  > instance paramDb: ParamDb base id 0x100
  > instance sensor: Sensor base id 0x200 queue size 10
  > topology T {
  >   instance paramDb
  >   instance sensor
  >   param connections instance paramDb
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:22:11 │ <tu>.T │ input port 'sensor.cmdIn' has no incoming         │
  │   │             │        │ connection                                        │
  │ ! │ t.fpp:21:11 │ <tu>.T │ input port 'paramDb.prmSetIn' has no incoming     │
  │   │             │        │ connection                                        │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 Pattern graph — telemetry connections (§7.3)

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > passive component TelemetryDb {
  >   sync input port tlmIn: Fw.Tlm
  > }
  > active component Sensor {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry Temperature: F64
  > }
  > instance telemetryDatabase: TelemetryDb base id 0x100
  > instance sensor: Sensor base id 0x200 queue size 10
  > topology T {
  >   instance telemetryDatabase
  >   instance sensor
  >   telemetry connections instance telemetryDatabase
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:14:11 │ <tu>.T │ input port 'telemetryDatabase.tlmIn' has no       │
  │   │             │        │ incoming connection                               │
  │ ! │ t.fpp:15:11 │ <tu>.T │ input port 'sensor.cmdIn' has no incoming         │
  │   │             │        │ connection                                        │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 Pattern graph — text event connections (§7.3)

  $ cat > t.fpp <<EOF
  > module Fw { port LogText }
  > passive component TextLogger {
  >   sync input port textIn: Fw.LogText
  > }
  > active component Sensor {
  >   async input port cmdIn: serial
  >   text event port textEventOut
  > }
  > instance textLogger: TextLogger base id 0x100
  > instance sensor: Sensor base id 0x200 queue size 10
  > topology T {
  >   instance textLogger
  >   instance sensor
  >   text event connections instance textLogger
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:12:11 │ <tu>.T │ input port 'textLogger.textIn' has no incoming    │
  │   │             │        │ connection                                        │
  │ ! │ t.fpp:13:11 │ <tu>.T │ input port 'sensor.cmdIn' has no incoming         │
  │   │             │        │ connection                                        │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 Pattern graph — time connections (§7.3)

  $ cat > t.fpp <<EOF
  > module Fw { port Time }
  > passive component TimeSource {
  >   output port timeOut: Fw.Time
  > }
  > active component Sensor {
  >   async input port cmdIn: serial
  >   time get port timeGet
  > }
  > instance timeSource: TimeSource base id 0x100
  > instance sensor: Sensor base id 0x200 queue size 10
  > topology T {
  >   instance timeSource
  >   instance sensor
  >   time connections instance timeSource
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:13:11: warning in SM '<tu>.T': input port 'sensor.cmdIn' has no incoming connection
  ✓ t.fpp

§5.14 Pattern graph with explicit target list (§7.3)

  $ cat > t.fpp <<EOF
  > module Fw { port Time }
  > passive component TimeSource {
  >   output port timeOut: [10] Fw.Time
  > }
  > active component SensorA {
  >   async input port cmdIn: serial
  >   time get port timeGet
  > }
  > active component SensorB {
  >   async input port cmdIn: serial
  >   time get port timeGet
  > }
  > instance timeSource: TimeSource base id 0x100
  > instance sensorA: SensorA base id 0x200 queue size 10
  > instance sensorB: SensorB base id 0x300 queue size 10
  > topology T {
  >   instance timeSource
  >   instance sensorA
  >   instance sensorB
  >   time connections instance timeSource { sensorA, sensorB }
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:18:11 │ <tu>.T │ input port 'sensorA.cmdIn' has no incoming        │
  │   │             │        │ connection                                        │
  │ ! │ t.fpp:19:11 │ <tu>.T │ input port 'sensorB.cmdIn' has no incoming        │
  │   │             │        │ connection                                        │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 CDH topology — from spec Example 1 (abbreviated)

  $ cat > t.fpp <<EOF
  > module Fw {
  >   port Cmd port CmdResponse port CmdReg
  >   port Log port LogText port Time port Tlm
  > }
  > passive component CommandDispatcher {
  >   output port cmdOut: [20] Fw.Cmd
  >   sync input port cmdRegIn: [20] Fw.CmdReg
  >   sync input port cmdRespIn: Fw.CmdResponse
  >   sync input port comCmdIn: [10] serial
  > }
  > active component CommandSequencer {
  >   async input port cmdIn: serial
  >   output port comCmdOut: serial
  >   command recv port cmdRecv
  >   command resp port cmdResp
  >   command reg port cmdReg
  >   event port eventOut
  >   telemetry port tlmOut
  >   time get port timeGet
  > }
  > passive component EventLogger {
  >   sync input port logIn: Fw.Log
  >   output port comOut: serial
  > }
  > passive component TimeSource {
  >   output port timeOut: Fw.Time
  > }
  > passive component SocketGround {
  >   sync input port comEventIn: serial
  >   sync input port comTlmIn: serial
  >   output port comCmdOut: serial
  > }
  > instance commandDispatcher: CommandDispatcher base id 0x100
  > instance commandSequencer: CommandSequencer base id 0x200 \
  >   queue size 10
  > instance eventLogger: EventLogger base id 0x300
  > instance timeSource: TimeSource base id 0x400
  > instance socketGroundInterface: SocketGround base id 0x500
  > topology CDH {
  >   instance commandDispatcher
  >   instance commandSequencer
  >   instance eventLogger
  >   instance timeSource
  >   private instance socketGroundInterface
  >   command connections instance commandDispatcher
  >   event connections instance eventLogger
  >   time connections instance timeSource
  >   connections CommandSequences {
  >     commandSequencer.comCmdOut -> commandDispatcher.comCmdIn
  >   }
  >   connections Downlink {
  >     eventLogger.comOut -> socketGroundInterface.comEventIn
  >   }
  >   connections Uplink {
  >     socketGroundInterface.comCmdOut -> commandDispatcher.comCmdIn
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬──────────┬─────────────────────────────────────────────────╮
  │   │ Location    │ SM       │ Warning                                         │
  ├───┼─────────────┼──────────┼─────────────────────────────────────────────────┤
  │ ! │ t.fpp:39:11 │ <tu>.CDH │ input port 'commandDispatcher.cmdRespIn' has no │
  │   │             │          │ incoming connection                             │
  │ ! │ t.fpp:39:11 │ <tu>.CDH │ input port 'commandDispatcher.cmdRegIn' has no  │
  │   │             │          │ incoming connection                             │
  │ ! │ t.fpp:43:19 │ <tu>.CDH │ input port 'socketGroundInterface.comTlmIn' has │
  │   │             │          │ no incoming connection                          │
  ╰───┴─────────────┴──────────┴─────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 Topology import — from spec Example 2

  $ cat > t.fpp <<EOF
  > passive component A { }
  > passive component B { }
  > instance a: A base id 0x100
  > instance b: B base id 0x200
  > topology Sub { instance a private instance b }
  > topology Main { import Sub instance a }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§5.14 Telemetry packet sets — from spec §7.15 example

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > active component CommandDispatcher {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry commandsDispatched: U32
  > }
  > active component RateGroup {
  >   async input port cycleIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry rgMaxTime: U32
  > }
  > active component Adcs {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry mode: U32
  >   telemetry attitude: F64
  >   telemetry extraTelemetry: U32
  > }
  > instance commandDispatcher: CommandDispatcher base id 0x100 \
  >   queue size 10
  > instance rateGroup1Hz: RateGroup base id 0x200 queue size 10
  > instance adcs: Adcs base id 0x300 queue size 10
  > topology T {
  >   instance commandDispatcher
  >   instance rateGroup1Hz
  >   instance adcs
  >   telemetry packets Packets {
  >     packet CDH id 0 group 0 {
  >       commandDispatcher.commandsDispatched
  >       rateGroup1Hz.rgMaxTime
  >     }
  >     packet ADCS id 1 group 2 {
  >       adcs.mode
  >       adcs.attitude
  >     }
  >   } omit {
  >     adcs.extraTelemetry
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬────────┬───────────────────────────────────────────────────╮
  │   │ Location    │ SM     │ Warning                                           │
  ├───┼─────────────┼────────┼───────────────────────────────────────────────────┤
  │ ! │ t.fpp:28:11 │ <tu>.T │ input port 'adcs.cmdIn' has no incoming           │
  │   │             │        │ connection                                        │
  │ ! │ t.fpp:26:11 │ <tu>.T │ input port 'commandDispatcher.cmdIn' has no       │
  │   │             │        │ incoming connection                               │
  │ ! │ t.fpp:27:11 │ <tu>.T │ input port 'rateGroup1Hz.cycleIn' has no incoming │
  │   │             │        │ connection                                        │
  ╰───┴─────────────┴────────┴───────────────────────────────────────────────────╯
  
  ✓ t.fpp

§5.14 Telemetry packet — group is required, id is optional

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > active component S {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry A: U32
  > }
  > instance s: S base id 0x100 queue size 10
  > topology T {
  >   instance s
  >   telemetry packets Pkts {
  >     packet P group 0 { s.A }
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:10:11: warning in SM '<tu>.T': input port 's.cmdIn' has no incoming connection
  ✓ t.fpp

§5.14 Instance param overrides — native FPP per-topology configuration

  $ cat > t.fpp <<'EOF'
  > port BlockConnect(name: string)
  > passive component Block {
  >   sync input port connect: BlockConnect
  > }
  > instance blk: Block base id 0
  > topology T1 {
  >   instance blk(name = "disk-a")
  > }
  > topology T2 {
  >   instance blk(name = "disk-b")
  > }
  > EOF
  $ ofpp check t.fpp
  ╭───┬─────────────┬─────────┬──────────────────────────────────────────────────╮
  │   │ Location    │ SM      │ Warning                                          │
  ├───┼─────────────┼─────────┼──────────────────────────────────────────────────┤
  │ ! │ t.fpp:7:11  │ <tu>.T1 │ input port 'blk.connect' has no incoming         │
  │   │             │         │ connection                                       │
  │ ! │ t.fpp:10:11 │ <tu>.T2 │ input port 'blk.connect' has no incoming         │
  │   │             │         │ connection                                       │
  ╰───┴─────────────┴─────────┴──────────────────────────────────────────────────╯
  
  ✓ t.fpp


§5.14 Instance param overrides — multiple params with mixed types

  $ cat > t.fpp <<'EOF'
  > port NetConnect(ipv4Only: bool, ipv6Only: bool, _0: string)
  > passive component Net {
  >   sync input port connect: NetConnect
  > }
  > instance net: Net base id 0
  > topology T {
  >   instance net(ipv4Only = false, ipv6Only = true, _0 = "tap0")
  > }
  > EOF
  $ ofpp check t.fpp
  ! t.fpp:7:11: warning in SM '<tu>.T': input port 'net.connect' has no incoming connection
  ✓ t.fpp

§5.14 Telemetry packet — missing group is a syntax error

  $ cat > t.fpp <<EOF
  > module Fw { port Tlm port Time }
  > active component S {
  >   async input port cmdIn: serial
  >   telemetry port tlmOut
  >   time get port timeGet
  >   telemetry A: U32
  > }
  > instance s: S base id 0x100 queue size 10
  > topology T {
  >   instance s
  >   telemetry packets Pkts {
  >     packet P { s.A }
  >   }
  > }
  > EOF
  $ ofpp check t.fpp
  ✗ t.fpp:12:14: syntax error
  
  ✗ 1/1 file failed
  [1]


FPP Spec §13 — Comments and Annotations
========================================

§13.1 Pre-annotations

  $ cat > t.fpp <<EOF
  > @ This is a documentation comment
  > constant x = 42
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§13.1 Multi-line pre-annotations

  $ cat > t.fpp <<EOF
  > @ Line one
  > @ Line two
  > @ Line three
  > constant documented = 42
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§13.2 Post-annotations

  $ cat > t.fpp <<EOF
  > constant x = 42 @< This is a post-annotation
  > enum Color {
  >   Red @< The color red
  >   Green @< The color green
  >   Blue @< The color blue
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§13.3 Mixed pre and post annotations

  $ cat > t.fpp <<EOF
  > @ A struct with mixed annotations
  > struct Config {
  >   @ The name field
  >   name: string @< must not be empty
  >   @ The value field
  >   value: U32 @< defaults to zero
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§13.4 Annotations on enum constants

  $ cat > t.fpp <<EOF
  > @ Status codes for the system
  > enum Status {
  >   @ All is well
  >   Ok @< no error
  >   @ Something went wrong
  >   Error @< general error
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§13.5 Annotations on component members

  $ cat > t.fpp <<EOF
  > @ A sensor component
  > passive component Sensor {
  >   @ Input data port
  >   sync input port dataIn: serial
  >   @ Output status
  >   output port status: serial
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§13.6 Custom annotations (ofpp extensions)

  $ cat > t.fpp <<EOF
  > @ ocaml.type Macaddr.t
  > type Mac
  > @ ocaml.sig Ethernet.S
  > passive component EthMake {
  >   sync input port connect: serial
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

FPP Spec §9 — Type Names
========================

§9.1 Primitive integer types

  $ cat > t.fpp <<EOF
  > struct Ints {
  >   a: I8, b: I16, c: I32, d: I64,
  >   e: U8, f: U16, g: U32, h: U64
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§9.2 Primitive float types

  $ cat > t.fpp <<EOF
  > struct Floats { x: F32, y: F64 }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§9.3 Bool type

  $ cat > t.fpp <<EOF
  > struct Flags { enabled: bool, on: bool }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§9.4 String type — bare and with size

  $ cat > t.fpp <<EOF
  > struct Strings {
  >   name: string,
  >   short: string size 32,
  >   long: string size 1024
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§9.5 Qualified type names

  $ cat > t.fpp <<EOF
  > module Types {
  >   enum Status { Ok, Error }
  >   struct Point { x: F64, y: F64 }
  > }
  > struct Config {
  >   status: Types.Status,
  >   origin: Types.Point
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

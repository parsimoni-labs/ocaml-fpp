FPP Spec §14 — Translation Units
=================================

§14.1 Empty translation unit

  $ cat > t.fpp <<EOF
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§14.2 Translation unit with top-level members

  $ cat > t.fpp <<EOF
  > constant A = 1
  > type T
  > type Alias = U32
  > enum E { X, Y }
  > struct S { v: U32 }
  > array Arr = [3] U32
  > port P
  > module M { constant B = 2 }
  > passive component C { }
  > instance c: C base id 0x100
  > topology Top { instance c }
  > state machine Sm {
  >   signal Go
  >   state Idle { on Go enter Idle }
  >   initial enter Idle
  > }
  > interface I { sync input port connect: serial }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§14.3 Multiple files (multi-file check)

  $ cat > a.fpp <<EOF
  > passive component A { }
  > EOF
  $ cat > b.fpp <<EOF
  > instance a: A base id 0x100
  > topology T { instance a }
  > EOF
  $ ofpp check a.fpp b.fpp
  ✓ a.fpp
  ✓ b.fpp
  
  ✓ 2 files ok

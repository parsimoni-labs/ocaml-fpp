FPP Spec §10 — Expressions
==========================

§10.1 Literal expressions

  $ cat > t.fpp <<EOF
  > constant i = 42
  > constant f = 3.14
  > constant s = "hello"
  > constant b = true
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.2 Identifier expressions

  $ cat > t.fpp <<EOF
  > constant a = 10
  > constant b = a
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.3 Dot expressions (qualified names)

  $ cat > t.fpp <<EOF
  > module Config { constant MAX = 100 }
  > constant limit = Config.MAX
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.4 Arithmetic expressions — binary operators

  $ cat > t.fpp <<EOF
  > constant a = 1 + 2
  > constant b = 10 - 3
  > constant c = 4 * 5
  > constant d = 20 / 4
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.4 Arithmetic expressions — unary minus

  $ cat > t.fpp <<EOF
  > constant a = 5
  > constant b = -a
  > constant c = -42
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.5 Parenthesized expressions

  $ cat > t.fpp <<EOF
  > constant x = (1 + 2) * 3
  > constant y = -(x + 1)
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.6 Array expressions

  $ cat > t.fpp <<EOF
  > array A = [3] U32 default [1, 2, 3]
  > array B = [2] F64 default [1.0, 2.0]
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.7 Struct expressions

  $ cat > t.fpp <<EOF
  > struct Point { x: F64, y: F64 }
  > struct Config {
  >   origin: Point
  > } default { origin = { x = 0.0, y = 0.0 } }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§10.8 Mixed nested expressions

  $ cat > t.fpp <<EOF
  > constant N = 3
  > array Vals = [N] U32 default [1 + 2, N * 4, 10 / 2]
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

FPP Spec §3 — Lexical Elements
===============================

§3.1 Reserved words — all keywords are recognised by the lexer

  $ cat > t.fpp <<EOF
  > # All reserved words used in valid contexts are tested across spec files.
  > # This test verifies a selection of keywords used as constants' names
  > # via the contextual keyword mechanism.
  > constant entry = 1
  > constant exit = 2
  > constant state = 3
  > constant action = 4
  > constant guard = 5
  > constant signal = 6
  > constant machine = 7
  > constant phase = 8
  > constant format = 9
  > constant id = 10
  > constant size = 11
  > constant time = 12
  > constant on = 13
  > constant change = 14
  > constant high = 15
  > constant low = 16
  > constant red = 17
  > constant orange = 18
  > constant yellow = 19
  > constant always = 20
  > constant block = 21
  > constant drop = 22
  > constant hook = 23
  > constant base = 24
  > constant cpu = 25
  > constant stack = 26
  > constant queue = 27
  > constant group = 28
  > constant text = 29
  > constant get = 30
  > constant set = 31
  > constant send = 32
  > constant recv = 33
  > constant resp = 34
  > constant reg = 35
  > constant save = 36
  > constant seconds = 37
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.3 Identifiers — escaped keywords with $ prefix

  $ cat > t.fpp <<'EOF'
  > constant $type = 42
  > constant $state = 100
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.3 Escaped keywords in port params and struct fields

  $ cat > t.fpp <<'EOF'
  > port HttpConnect($port: U16, $type: string)
  > struct Config { $port: U16, $type: string }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.5 Comments — hash comments

  $ cat > t.fpp <<EOF
  > # This is a comment
  > constant x = 42 # inline comment
  > # Another comment
  > enum Color { Red, Green, Blue }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.7 Explicit line continuations — backslash before newline

  $ cat > t.fpp <<EOF
  > constant long_name = \
  >   42 + \
  >   58
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.2 Integer literals — decimal and hex

  $ cat > t.fpp <<EOF
  > constant dec = 42
  > constant hex1 = 0xFF
  > constant hex2 = 0X1A
  > constant neg = -42
  > constant zero = 0
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.2 Float literals

  $ cat > t.fpp <<EOF
  > constant pi = 3.14159
  > constant small = .001
  > constant whole = 42.
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.2 String literals — single-line and multiline

  $ cat > t.fpp <<EOF
  > constant greeting = "hello world"
  > constant escaped = "line1\nline2\ttab"
  > passive component Doc { }
  > instance doc: Doc base id 0x100 {
  >   phase 1 """
  >     multi
  >     line
  >     init
  >   """
  > }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§3.2 Boolean literals

  $ cat > t.fpp <<EOF
  > constant flag = true
  > constant other = false
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

§4 Element sequences — semicolons as optional separators

  $ cat > t.fpp <<EOF
  > constant a = 1; constant b = 2
  > enum Color { Red; Green; Blue }
  > EOF
  $ ofpp check t.fpp
  ✓ t.fpp

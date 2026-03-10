Parse a valid FPP file
  $ cat > hello.fpp <<EOF
  > constant x = 42
  > EOF
  $ ofpp check hello.fpp
  ✓ hello.fpp

Parse a valid FPP file with verbose output
  $ ofpp check -v hello.fpp
  ✓ hello.fpp (0 components, 0 state machines, 0 topologies)

Parse multiple files
  $ cat > a.fpp <<EOF
  > enum Color { Red, Green, Blue }
  > EOF
  $ cat > b.fpp <<EOF
  > struct Point { x: F64, y: F64 }
  > EOF
  $ ofpp check a.fpp b.fpp
  ✓ a.fpp
  ✓ b.fpp
  
  ✓ 2 files ok



Report syntax errors
  $ cat > bad.fpp <<EOF
  > constant x =
  > EOF
  $ ofpp check bad.fpp
  ✗ bad.fpp:2:0: syntax error
  
  ✗ 1/1 file failed
  [1]



Mix of valid and invalid files
  $ ofpp check hello.fpp bad.fpp
  ✗ bad.fpp:2:0: syntax error
  [1]



Verbose output with a component
  $ cat > comp.fpp <<EOF
  > passive component Led { }
  > EOF
  $ ofpp check -v comp.fpp
  ✓ comp.fpp (1 component, 0 state machines, 0 topologies)

Missing file
  $ (r=$(ofpp check nonexistent.fpp 2>&1); rc=$?; printf '%s\n' "$r" | sed "s/'//g"; exit $rc)
  Usage: ofpp check [--help] [--error=SPEC] [--verbose] [--warning=SPEC]
         [OPTION]… FILE…
  ofpp: FILE… arguments: no nonexistent.fpp file or directory
  [1]

No arguments
  $ (r=$(ofpp check 2>&1); rc=$?; printf '%s\n' "$r" | sed "s/'//g"; exit $rc)
  Usage: ofpp check [--help] [--error=SPEC] [--verbose] [--warning=SPEC]
         [OPTION]… FILE…
  ofpp: required argument FILE is missing
  [1]

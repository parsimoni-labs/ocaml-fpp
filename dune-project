(lang dune 3.0)

(using menhir 2.1)

(name fpp)

(generate_opam_files true)

(license MIT)

(authors "Thomas Gazagnaire")

(maintainers "Thomas Gazagnaire")

(source
 (github nasa/fpp-ocaml))

(package
 (name fpp)
 (synopsis "Static analysis and test generation for NASA F Prime FPP models")
 (description
  "FPP parser, static analysis (state machine reachability, deadlock detection, topology checks), and test generation for NASA F Prime models.")
 (depends
  (ocaml
   (>= 4.14))
  fmt
  menhir
  menhirLib
  cmdliner
  logs
  (alcotest :with-test)))

(lang dune 3.0)

(using menhir 2.1)

(name fpp)

(generate_opam_files true)

(license MIT)

(authors "Thomas Gazagnaire")

(maintainers "Thomas Gazagnaire")

(source
 (github parsimoni-labs/ocaml-fpp))

(package
 (name fpp)
 (synopsis "Static analysis and test generation for NASA F Prime FPP models")
 (description
  "FPP parser, static analysis (state machine reachability, deadlock detection, topology checks), and test generation for NASA F Prime models.")
 (depends
  (ocaml
   (>= 4.14))
  fmt
  jsont
  menhir
  menhirLib
  cmdliner
  logs
  tty
  (alcotest :with-test)
  (memtrace :with-test)
  (lwt :with-test)
  (cstruct :with-test)
  (macaddr :with-test)
  (mirage-block :with-test)
  (mirage-vnetif :with-test)
  (ethernet :with-test)
  (arp :with-test)
  (conduit-mirage :with-test)
  (cohttp-mirage :with-test)
  (tar-mirage :with-test)
  (tcpip :with-test)
  (mirage-kv :with-test)
  (mirage-kv-mem :with-test)
  (happy-eyeballs-mirage :with-test)
  (dns-client-mirage :with-test)
  (mirage-runtime :with-test)
  (mirage-bootvar :with-test)
  (cmdliner-stdlib :with-test)
  (mirage-logs :with-test)
  (mirage-unix :with-test)
  (mirage-crypto-rng-mirage (and (>= 2.0.0) :with-test))
  (mirage-crypto-rng (and (>= 2.0.0) :with-test))
  (duration :with-test)
  (mirage-sleep :with-test)
  (mirage-mtime :with-test)
  (mirage-ptime :with-test)
  (mirage-block-ramdisk :with-test)
  (mirage-net-unix :with-test)
  (mirage-solo5 :with-test)
  (mirage-net-solo5 :with-test)
  (uri :with-test)
  (ipaddr :with-test)
  (charrua :with-test)
  (charrua-server :with-test)
  (ocaml-crunch :with-test)
  (dune-build-info :with-test)
  (chamelon :with-test)
  (hxd :with-test)
  (mirage-block-unix :with-test)
  (mirage-flow :with-test)))

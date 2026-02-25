Extract and compile topologies from the MirageOS example.

Setup
  $ compile() { ocamlopt -w -a sm.ml -o sm.exe 2>&1; }
  $ run() { ./sm.exe 2>&1; }

Create shared mock stubs for Lwt and MirageOS component functors.
  $ cat > mock.ml <<'MOCK'
  > module Lwt = struct
  >   type 'a t = 'a
  >   let return x = x
  >   let map f x = f x
  >   module Syntax = struct let ( let* ) x f = f x end
  > end
  > module Lwt_main = struct let run x = ignore x end
  > module Vnetif = struct
  >   module Make(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Ethernet = struct
  >   module Make(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Arp = struct
  >   module Make(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Static_ipv4 = struct
  >   module Make(_ : sig type t end)(_ : sig type t end) = struct
  >     type t = unit
  >     let connect ~cidr:_ _ _ = ()
  >   end
  > end
  > module Ipv6 = struct
  >   module Make(_ : sig type t end)(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ _ = ()
  >   end
  > end
  > module Tcpip_stack_direct = struct
  >   module IPV4V6(_ : sig type t end)(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ _ = ()
  >   end
  >   module MakeV4V6
  >     (_ : sig type t end)(_ : sig type t end)(_ : sig type t end)
  >     (_ : sig type t end)(_ : sig type t end)(_ : sig type t end)
  >     (_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ _ _ _ _ _ _ = ()
  >   end
  > end
  > module Icmpv4 = struct
  >   module Make(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Udp = struct
  >   module Make(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Tcp = struct
  >   module Flow = struct
  >     module Make(_ : sig type t end) = struct
  >       type t = unit
  >       let connect _ = ()
  >     end
  >   end
  > end
  > module Conduit_mirage = struct
  >   module TCP(_ : sig type t end) = struct type t = unit end
  >   module TLS(_ : sig type t end) = struct type t = unit end
  > end
  > module Cohttp_mirage = struct
  >   module Server = struct
  >     module Make(_ : sig type t end) = struct type t = unit end
  >   end
  > end
  > module Happy_eyeballs_mirage = struct
  >   module Make(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Dns_client_mirage = struct
  >   module Make(_ : sig type t end)(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ _ = ()
  >   end
  > end
  > module Tar_mirage = struct
  >   module Make_KV_RO(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Fat = struct
  >   module KV_RO(_ : sig type t end) = struct
  >     type t = unit
  >     let connect _ = ()
  >   end
  > end
  > module Server = struct
  >   module Unix_socket_stack = struct
  >     type t = unit
  >     let connect () = ()
  >   end
  > end
  > module Htdocs_data = struct
  >   type t = unit
  >   let connect () = ()
  > end
  > module Tls_data = struct
  >   type t = unit
  >   let connect () = ()
  > end
  > module Mirage_kv_mem = struct
  >   type t = unit
  >   let connect () = ()
  > end
  > MOCK

Types-only mode: module types compile on their own
  $ ofpp to-ml --types data/mirage.fpp > sm.ml
  $ compile && echo "types: OK"
  types: OK

Single fully-bound topology (UnixTestWebsite)
  $ cat mock.ml > sm.ml
  $ ofpp to-ml --topologies UnixTestWebsite data/mirage.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > let () = print_endline "unix_test: OK"
  > TEST
  $ compile && run
  unix_test: OK

Fully-bound topology with DNS (UnixWebsiteWithDns)
  $ cat mock.ml > sm.ml
  $ ofpp to-ml --topologies UnixWebsiteWithDns data/mirage.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > let () = print_endline "unix_dns: OK"
  > TEST
  $ compile && run
  unix_dns: OK

Two fully-bound topologies with multi-entry point
  $ cat mock.ml > sm.ml
  $ ofpp to-ml --topologies UnixWebsite,UnixTestWebsite data/mirage.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > let () = print_endline "multi_bound: OK"
  > TEST
  $ compile && run
  multi_bound: OK

Parameterised sub-topology (TcpipStack): functor with Backend leaf
  $ cat mock.ml > sm.ml
  $ ofpp to-ml --types data/mirage.fpp >> sm.ml
  $ ofpp to-ml --topologies TcpipStack data/mirage.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > module B = struct
  >   type t = unit
  >   let provide () = ()
  > end
  > module App = Make(B)
  > let () =
  >   let t = App.connect ~cidr:() () in
  >   ignore t;
  >   print_endline "tcpip_stack: OK"
  > TEST
  $ compile && run
  tcpip_stack: OK

Composite topology (StaticWebsite): imports TcpipStack + HttpStack
  $ cat mock.ml > sm.ml
  $ ofpp to-ml --types data/mirage.fpp >> sm.ml
  $ ofpp to-ml --topologies StaticWebsite data/mirage.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > module B = struct
  >   type t = unit
  >   let provide () = ()
  > end
  > module K = struct
  >   type t = unit
  >   let disconnect () = ()
  >   let get () _ = ""
  >   let exists () _ = false
  >   let list () _ = ""
  >   let digest () _ = ""
  > end
  > module App = Make(B)(K)(K)
  > let () =
  >   let t = App.connect ~cidr:() () () () in
  >   ignore t;
  >   print_endline "static_website: OK"
  > TEST
  $ compile && run
  static_website: OK

Block-backed topology (TarWebsite): imports TcpipStack + HttpStack + DnsStack
  $ cat mock.ml > sm.ml
  $ ofpp to-ml --types data/mirage.fpp >> sm.ml
  $ ofpp to-ml --topologies TarWebsite data/mirage.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > module B = struct
  >   type t = unit
  >   let provide () = ()
  > end
  > module App = Make(B)(B)(B)
  > let () =
  >   let t = App.connect ~cidr:() () () () in
  >   ignore t;
  >   print_endline "tar_website: OK"
  > TEST
  $ compile && run
  tar_website: OK

FAT-backed topology (FatWebsite): different KV backend, no DNS
  $ cat mock.ml > sm.ml
  $ ofpp to-ml --types data/mirage.fpp >> sm.ml
  $ ofpp to-ml --topologies FatWebsite data/mirage.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > module B = struct
  >   type t = unit
  >   let provide () = ()
  > end
  > module App = Make(B)(B)(B)
  > let () =
  >   let t = App.connect ~cidr:() () () () in
  >   ignore t;
  >   print_endline "fat_website: OK"
  > TEST
  $ compile && run
  fat_website: OK

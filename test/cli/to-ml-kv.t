KV store topology variants: compile and run all backend patterns.

Setup
  $ compile() { local out; out=$(ocamlopt -w -23-32-26-27 sm.ml -o sm.exe 2>&1); local rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/Unbound module "\([^"]*\)"/Unbound module \1/g'; return $rc; }
  $ run() { ./sm.exe 2>&1; }

Create FPP with four KV topology variants: leaf parameter, bound module,
tar-over-block, fat-over-block.  Component names match the default functor
convention (Tar -> Tar.Make, Fat -> Fat.Make), so no annotations are needed.
  $ cat > kv.fpp <<'EOF'
  > port Dep
  > active component Service {
  >   output port data: Dep
  >   sync input port run: Dep
  > }
  > active component Kv {
  >   sync input port provide: Dep
  > }
  > active component Block {
  >   sync input port provide: Dep
  > }
  > active component Tar {
  >   output port block: Dep
  >   sync input port provide: Dep
  > }
  > active component Fat {
  >   output port block: Dep
  >   sync input port provide: Dep
  > }
  > module Mem {
  >   active component Store {
  >     sync input port provide: Dep
  >   }
  > }
  > instance service: Service base id 0x100
  > instance data: Kv base id 0x200
  > instance block: Block base id 0x300
  > instance tar_data: Tar base id 0x400
  > instance fat_data: Fat base id 0x500
  > instance mem_data: Mem.Store base id 0x600
  > topology LeafKv {
  >   instance service
  >   instance data
  >   connections C { service.data -> data.provide }
  > }
  > topology BoundKv {
  >   instance service
  >   instance mem_data
  >   connections C { service.data -> mem_data.provide }
  > }
  > topology TarKv {
  >   instance service
  >   instance block
  >   instance tar_data
  >   connections C {
  >     service.data -> tar_data.provide
  >     tar_data.block -> block.provide
  >   }
  > }
  > topology FatKv {
  >   instance service
  >   instance block
  >   instance fat_data
  >   connections C {
  >     service.data -> fat_data.provide
  >     fat_data.block -> block.provide
  >   }
  > }
  > EOF

Compile and run all four variants.  Stubs provide minimal Lwt,
functor implementations, and a concrete module for the bound case.
  $ cat > sm.ml <<'STUBS'
  > module Lwt = struct
  >   type 'a t = 'a
  >   let return x = x
  >   module Syntax = struct let ( let* ) x f = f x end
  > end
  > module Service = struct
  >   module Make (K : sig type t end) = struct
  >     type t = { srv_dep : K.t }
  >     let run _ = ()
  >     let connect k = { srv_dep = k }
  >   end
  > end
  > module Tar = struct
  >   module Make (B : sig type t end) = struct
  >     type t = { tar_block : B.t }
  >     let provide _ = ()
  >     let connect b = { tar_block = b }
  >   end
  > end
  > module Fat = struct
  >   module Make (B : sig type t end) = struct
  >     type t = { fat_block : B.t }
  >     let provide _ = ()
  >     let connect b = { fat_block = b }
  >   end
  > end
  > module Mem = struct
  >   module Store = struct
  >     type t = { mem_id : int }
  >     let provide _ = ()
  >     let connect () = { mem_id = 1 }
  >   end
  > end
  > STUBS
  $ ofpp to-ml kv.fpp >> sm.ml
  $ cat >> sm.ml <<'TEST'
  > let () =
  >   let module M = LeafKv.Make(struct
  >     type t = int
  >     let provide _ = ()
  >   end) in
  >   let v = M.c 42 in
  >   assert (v.data = 42);
  >   print_endline "leaf_kv: OK";
  >   let mem_data = Lazy.force BoundKv.mem_data in
  >   assert (mem_data.mem_id = 1);
  >   print_endline "bound_kv: OK";
  >   let module T = TarKv.Make(struct
  >     type t = string
  >     let provide _ = ()
  >   end) in
  >   let v = T.c "disk0" in
  >   assert (v.block = "disk0");
  >   assert (v.tar_data.tar_block = "disk0");
  >   print_endline "tar_kv: OK";
  >   let module F = FatKv.Make(struct
  >     type t = string
  >     let provide _ = ()
  >   end) in
  >   let v = F.c "disk1" in
  >   assert (v.block = "disk1");
  >   assert (v.fat_data.fat_block = "disk1");
  >   print_endline "fat_kv: OK"
  > TEST
  $ compile && run
  File "sm.ml", line 38, characters 30-34:
  38 | module Service = Service.Make(Data)
                                     ^^^^
  Error: Unbound module Data
  [2]

(* Minimal in-memory block device for topology tests.

   Satisfies [Mirage_block.S] with a zeroed buffer.  Read returns
   zeros, write is rejected as read-only. *)

type error = [ `Disconnected ]
type write_error = [ `Disconnected | `Is_read_only ]

let pp_error fmt `Disconnected = Fmt.string fmt "disconnected"

let pp_write_error fmt = function
  | `Disconnected -> Fmt.string fmt "disconnected"
  | `Is_read_only -> Fmt.string fmt "read-only"

type t = { sector_size : int; sectors : int }

let connect () : t Lwt.t = Lwt.return { sector_size = 512; sectors = 64 }
let disconnect _ = Lwt.return_unit

let get_info t =
  let info : Mirage_block.info =
    {
      read_write = false;
      sector_size = t.sector_size;
      size_sectors = Int64.of_int t.sectors;
    }
  in
  Lwt.return info

let read _t _sector bufs =
  List.iter (fun buf -> Cstruct.memset buf 0) bufs;
  Lwt.return (Ok ())

let write _t _sector _bufs = Lwt.return (Error `Is_read_only)

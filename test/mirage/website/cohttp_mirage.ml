(* Cohttp_mirage compilation-test stubs.

   Shadows the real cohttp-mirage library to provide connect signatures
   matching what ofpp generates. *)

module Server = struct
  module Make (S : sig
    type t
  end) =
  struct
    type t = S.t

    let connect (s : S.t) : t Lwt.t = Lwt.return s
  end
end

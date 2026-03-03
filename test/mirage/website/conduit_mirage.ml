(* Conduit_mirage compilation-test stubs.

   Shadows the real conduit-mirage library to provide connect signatures
   matching what ofpp generates: [connect dep1 dep2 ... : t Lwt.t]. *)

module type S = sig
  type t

  val connect : unit -> t Lwt.t
end

module TCP (S : sig
  type t
end) =
struct
  type t = S.t

  let connect (s : S.t) : t Lwt.t = Lwt.return s
end

module TLS (S : sig
  type t
end) =
struct
  type t = S.t

  let connect (s : S.t) : t Lwt.t = Lwt.return s
end

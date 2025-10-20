module type S = sig
  (** Minimal wall clock interface returning seconds. *)

  (** Return the current time in seconds. *)
  val now : unit -> float
end

(** Clock implementation backed by [Clock.Mtime] from the OCaml ecosystem. *)
module Mtime : S

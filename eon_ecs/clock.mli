module type S = sig
  (** Minimal wall clock interface returning seconds.

      This abstraction lets you swap real-time and deterministic clocks.
  *)

  (** Return the current time in seconds. *)
  val now : unit -> float
end

(** Clock implementation backed by [Mtime_clock]. *)
module Mtime : S

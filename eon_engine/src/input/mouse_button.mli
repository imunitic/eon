(** Engine-defined mouse buttons — backend-agnostic. *)

type t = Left | Right | Middle | Extra_1 | Extra_2

module Set : Set.S with type elt = t

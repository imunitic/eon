(** Platform-assigned identifier of one touch contact (finger or pen).

    Stable from the moment the contact lands until it lifts or is
    cancelled. Backends must not reuse an id while its contact is still
    held; reuse after release is allowed. *)

type t

(** Wrap a platform contact id. *)
val of_int : int -> t

val to_int : t -> int
val compare : t -> t -> int

module Set : Set.S with type elt = t
module Map : Map.S with type key = t

(** Generational entity identifier.

    IDs are stable handles composed of [index] + [generation]. The generation
    changes when an entity slot is reused, which prevents stale references from
    matching newly created entities.
*)

(** An opaque entity identifier, combining index and generation. *)
type t

(** Create an entity ID from index and generation.

    Example:
    {[
      let e = Entity_id.make 42 3 in
      assert (Entity_id.index e = 42)
    ]}
*)
val make : int -> int -> t

(** Get the index portion of the ID. *)
val index : t -> int

(** Get the generation portion of the ID. *)
val generation : t -> int

(** Compare two IDs for equality. *)
val equal : t -> t -> bool

(** Sentinel invalid entity ID. *)
val invalid : t

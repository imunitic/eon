(** Tag component for Eon Engine.

    Attaches a human-readable name to an entity. Useful for debugging,
    scripting lookups, and grouping entities by role without defining
    separate component types.
*)

type t = {
  name : string;  (** Arbitrary label for the entity. *)
}

val component : t Component_descriptor.t

(** Tag component for Eon Engine.

    Attaches a human-readable label to an entity. Useful for debugging,
    scripting lookups, and grouping entities by role without defining
    separate component types.
*)

type t = {
  value : string;  (** Arbitrary label for the entity (e.g. "player", "enemy", "bullet"). *)
}

val component : t Component_descriptor.t

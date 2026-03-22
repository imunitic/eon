(** Lifetime component for Eon Engine.

    Tracks how many seconds remain before an entity should be destroyed.
    A lifetime system decrements [remaining] by [dt] each frame and calls
    [World.destroy_entity] when it reaches zero.
*)

type t = {
  remaining : float;  (** Seconds until the entity is destroyed. *)
}

val component : t Component_descriptor.t

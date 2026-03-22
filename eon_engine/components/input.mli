(** Input component for Eon Engine.

    Marks an entity as player-controlled and identifies which player drives it.
    Actual input state (key/axis values) is read from a world resource by an
    input system, which then writes derived values (e.g. [Velocity]) back via
    commands. This keeps the component frame-agnostic and free of platform
    dependencies.
*)

type t = {
  player_id : int;  (** Index of the player or gamepad controlling this entity. *)
}

val component : t Component_descriptor.t

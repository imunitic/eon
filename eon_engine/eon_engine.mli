(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

(** Module-based component registration API. *)
module Components = Components

(** Check if a component is registered in the world. *)
val is_registered : Eon_ecs.World.t -> 'a Components.t -> bool

(** Create a component descriptor with a given name.

    This is a convenience alias for [Components.component].
    
    Example:
    {[
      module Position = struct
        type t = { x : float; y : float }
        let component = Engine.component "Position"
      end
    ]}
*)
val component : string -> 'a Components.t

(** Register a component descriptor with a world.

    Uses an automatically generated ID.
    
    Example:
    {[
      Engine.register world Position.component
    ]}
*)
val register : Eon_ecs.World.t -> 'a Components.t -> Components.registration_result
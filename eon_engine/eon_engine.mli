(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

(** Module-based component registration API. *)
module Components = Components

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

(** Register a component descriptor with a world using an explicit ID.

    This is a convenience alias for [Components.register_component].
    
    Example:
    {[
      Engine.register_component world Position.component ~id:0
    ]}
*)
val register_component : Eon_ecs.World.t -> 'a Components.t -> id:int -> Components.registration_result

(** Register a component descriptor with a world using an automatically generated ID.

    This is a convenience alias for [Components.register].
    
    Example:
    {[
      Engine.register world Position.component
    ]}
*)
val register : Eon_ecs.World.t -> 'a Components.t -> Components.registration_result
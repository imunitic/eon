(** Typed component registration API for Eon Engine.

    This module provides a module-based component registration API that
    enables strong typing and easy modular composition. Components are
    defined as modules with a simple interface.

    Registration is world-scoped (no hidden global registry) and operations
    are idempotent.
*)

(** Re-export the component descriptor type and operations. *)
include module type of Component_descriptor

(** 2D position component. *)
module Position : module type of Position

(** 2D velocity component. *)
module Velocity : module type of Velocity

(** 2D acceleration component. *)
module Acceleration : module type of Acceleration

(** Rotation component (angle in radians). *)
module Rotation : module type of Rotation

(** 2D scale component. *)
module Scale : module type of Scale

(** Health component. *)
module Health : module type of Health

(** Mana component (magic/energy resource). *)
module Mana : module type of Mana

(** Team affiliation component. *)
module Team : module type of Team

(** Entity ownership component. *)
module Owner : module type of Owner

(** Sprite rendering component. *)
module Sprite : module type of Sprite

(** Sprite animation component. *)
module Animation : module type of Animation

(** Camera component. *)
module Camera : module type of Camera

(** Camera target component. *)
module Camera_target : module type of Camera_target

(** Engine component framework.

    This module provides built-in components and the foundation for component
    grouping patterns. It includes Position, Velocity, Acceleration, Rotation,
    Scale, Health, Mana, Team, and Owner components.
    
    Game developers should create their own component modules following this pattern:
    - Define components with [Engine.component]
    - Provide a [register_all] function
    - Use [include] to compose component groups
    
    Example of game-level component assembly:
    {[
      module Game_components = struct
        include Engine_components  (* Includes all built-in components *)
        
        let portal = Engine.component "Portal"
        let health = Engine.component "CustomHealth"  (* Different name than built-in Health *)
        
        let register_all world =
          Engine_components.register_all world;  (* Registers all built-in components *)
          Engine.register world portal;
          Engine.register world health
      end
    ]}
*)
module Engine_components : sig
  (** Register all engine components with automatically generated IDs.
      
      Registers Position, Velocity, Acceleration, Rotation, Scale, Health,
      Mana, Team, Owner, Sprite, Animation, Camera, and Camera_target components.
  *)
  val register_all : Eon_ecs.World.t -> unit
end
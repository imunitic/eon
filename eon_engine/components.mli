(** Typed component registration API for Eon Engine.

    This module provides a module-based component registration API that
    enables strong typing and easy modular composition. Components are
    defined as modules with a simple interface.

    Registration is world-scoped (no hidden global registry) and operations
    are idempotent.
*)

(** Signature for a component module.
    
    All component modules must conform to this signature to ensure
    consistent interface across the component system.
*)
module type S = sig
  type t
  val component : t Component_descriptor.t
  val name : string
end

(** Component descriptor type for typed component registration. *)
type 'a t = 'a Component_descriptor.t

(** Alias for component descriptor type. *)
type 'a component_descriptor = 'a Component_descriptor.component_descriptor

(** Registration result type. *)
type registration_result = Registered | Already_registered

(** Create a component descriptor with a given name. *)
val component : string -> 'a t

(** Register a component descriptor with a world. *)
val register : Eon_ecs.World.t -> 'a t -> registration_result

(** Check if a component is already registered in the world. *)
val is_registered : Eon_ecs.World.t -> 'a t -> bool

(** Get the name of a component descriptor. *)
val name : 'a t -> string

(** 2D position component. *)
module Position : S with type t = Position.t

(** 2D velocity component. *)
module Velocity : S with type t = Velocity.t

(** 2D acceleration component. *)
module Acceleration : S with type t = Acceleration.t

(** Rotation component (angle in radians). *)
module Rotation : S with type t = Rotation.t

(** 2D scale component. *)
module Scale : S with type t = Scale.t

(** Health component. *)
module Health : S with type t = Health.t

(** Mana component (magic/energy resource). *)
module Mana : S with type t = Mana.t

(** Team affiliation component. *)
module Team : S with type t = Team.t

(** Entity ownership component. *)
module Owner : S with type t = Owner.t

(** Sprite rendering component. *)
module Sprite : S with type t = Sprite.t

(** Sprite animation component. *)
module Animation : S with type t = Animation.t

(** Camera component. *)
module Camera : S with type t = Camera.t

(** Camera target component. *)
module Camera_target : S with type t = Camera_target.t

(** Collider component. *)
module Collider : S with type t = Collider.t

(** Tag component. *)
module Tag : S with type t = Tag.t

(** Lifetime component. *)
module Lifetime : S with type t = Lifetime.t

(** Input component. *)
module Input : S with type t = Input.t

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
      Mana, Team, Owner, Sprite, Animation, Camera, Camera_target, Collider,
      Tag, Lifetime, and Input components.
  *)
  val register_all : Eon_ecs.World.t -> unit
end
(** Typed component registration API for Eon Engine.

    This module provides a module-based component registration API that
    enables strong typing and easy modular composition. Components are
    defined as modules with a simple interface.

    Registration is world-scoped (no hidden global registry) and operations
    are idempotent.
*)

(** Re-export the component module signature. *)
module type S = Component.S

(** Component descriptor type for typed component registration. *)
type 'a t = 'a Component_descriptor.t

(** Alias for component descriptor type. *)
type 'a component_descriptor = 'a Component_descriptor.component_descriptor

(** Registration result type. *)
type registration_result = Component_descriptor.registration_result =
  Registered | Already_registered

(** Create a component descriptor with a given name. *)
val component : string -> 'a t

(** Get the name of a component descriptor. *)
val name : 'a t -> string

(** 2D position component. *)
module Position : S with type t = Position.t

(** 2D velocity component. *)
module Velocity : S with type t = Velocity.t

(** Rotation component (angle in radians). *)
module Rotation : S with type t = Rotation.t

(** 2D scale component. *)
module Scale : S with type t = Scale.t

(** Sprite rendering component. *)
module Sprite : S with type t = Sprite.t

(** Sprite animation component. *)
module Animation : S with type t = Animation.t

(** Camera component. *)
module Camera : S with type t = Camera.t

(** Collider component. *)
module Collider : S with type t = Collider.t

(** Tag component. *)
module Tag : S with type t = Tag.t

(** Engine component framework.

    This module provides built-in components and the foundation for component
    grouping patterns.

    Game developers should create their own component modules following this pattern:
    - Define components with [Engine.component]
    - Provide a [register_all] function
    - Use [include] to compose component groups

    Example of game-level component assembly:
    {[
      module Game_components = struct
        include Engine_components

        let health = Engine.component "Health"

        let register_all world =
          Engine_components.register_all world;
          World.register world health
      end
    ]}
*)
module Engine_components : sig
  (** Register all engine components with automatically generated IDs.

      Registers Position, Velocity, Rotation, Scale, Sprite, Animation,
      Camera, Collider, and Tag components.
  *)
  val register_all : World.t -> unit
end

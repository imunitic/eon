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

(** Local-space transform: position, rotation, and scale relative to parent.
    Written by game systems. If no [Parent] component is present, relative to world origin. *)
module Local_transform : S with type t = Local_transform.t

(** World-space transform: fully composed position in world space.
    Written only by [Transform_system]. Game code treats this as read-only. *)
module World_transform : S with type t = World_transform.t

(** Hierarchy parent reference. Absence means the entity is a root.
    Set directly at setup time; emit [`Reparent] on the command bus mid-simulation. *)
module Parent : S with type t = Parent.t

(** Engine-maintained cache of direct child entity IDs.
    Updated by [Transform_system] on [Reparent] and [Destroy_entity] commands.
    Game code reads but never writes. *)
module Children : S with type t = Children.t

(** 2D velocity component. *)
module Velocity : S with type t = Velocity.t

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

      Registers Local_transform, World_transform, Parent, Children, Velocity,
      Sprite, Animation, Camera, Collider, and Tag components.
  *)
  val register_all : World.rw World.t -> unit
end

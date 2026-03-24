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
    
    The values in this signature are implemented by the individual
    component modules, not by this module itself.
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
type registration_result = Component_descriptor.registration_result =
  Registered | Already_registered

(** Create a component descriptor with a given name. *)
let component = Component_descriptor.component

(** Register a component descriptor with a world. *)
let register = Component_descriptor.register

(** Check if a component is already registered in the world. *)
let is_registered = Component_descriptor.is_registered

(** Get the name of a component descriptor. *)
let name = Component_descriptor.name

(** 2D position component. *)
module Position = Position

(** 2D velocity component. *)
module Velocity = Velocity

(** 2D acceleration component. *)
module Acceleration = Acceleration

(** Rotation component (angle in radians). *)
module Rotation = Rotation

(** 2D scale component. *)
module Scale = Scale

(** Health component. *)
module Health = Health

(** Mana component (magic/energy resource). *)
module Mana = Mana

(** Team affiliation component. *)
module Team = Team

(** Entity ownership component. *)
module Owner = Owner

(** Sprite rendering component. *)
module Sprite = Sprite

(** Sprite animation component. *)
module Animation = Animation

(** Camera component. *)
module Camera = Camera

(** Camera target component. *)
module Camera_target = Camera_target

(** Collider component. *)
module Collider = Collider

(** Tag component. *)
module Tag = Tag

(** Lifetime component. *)
module Lifetime = Lifetime

(** Input component. *)
module Input = Input

(** Built-in engine components. *)
module Engine_components = struct
  (** Register all engine components with automatically generated IDs. *)
  let register_all world =
    ignore (register world Position.component);
    ignore (register world Velocity.component);
    ignore (register world Acceleration.component);
    ignore (register world Rotation.component);
    ignore (register world Scale.component);
    ignore (register world Health.component);
    ignore (register world Mana.component);
    ignore (register world Team.component);
    ignore (register world Owner.component);
    ignore (register world Sprite.component);
    ignore (register world Animation.component);
    ignore (register world Camera.component);
    ignore (register world Camera_target.component);
    ignore (register world Collider.component);
    ignore (register world Tag.component);
    ignore (register world Lifetime.component);
    ignore (register world Input.component)
end
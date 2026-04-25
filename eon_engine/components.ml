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
let component = Component_descriptor.component

(** Register a component descriptor with a world. *)
let register = Component_descriptor.register

(** Check if a component is already registered in the world. *)
let is_registered = Component_descriptor.is_registered

(** Get the name of a component descriptor. *)
let name = Component_descriptor.name

(** 2D position component. *)
module Position = Position
module Velocity = Velocity
module Rotation = Rotation
module Scale = Scale
module Sprite = Sprite
module Animation = Animation
module Camera = Camera
module Collider = Collider
module Tag = Tag

(** Built-in engine components. *)
module Engine_components = struct
  (** Register all engine components with automatically generated IDs. *)
  let register_all world =
    let components : (module S) list = [
      (module Position : S);
      (module Velocity : S);
      (module Rotation : S);
      (module Scale : S);
      (module Sprite : S);
      (module Animation : S);
      (module Camera : S);
      (module Collider : S);
      (module Tag : S);
    ] in
    List.iter (fun (module Comp : S) ->
      ignore (register world Comp.component)
    ) components
end


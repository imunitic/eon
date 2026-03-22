(** Typed component registration API for Eon Engine.

    This module provides a module-based component registration API that
    enables strong typing and easy modular composition. Components are
    defined as modules with a simple interface.

    Registration is world-scoped (no hidden global registry) and operations
    are idempotent.
*)

(** Re-export the component descriptor type and operations. *)
include Component_descriptor

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
    ignore (register world Owner.component)
end
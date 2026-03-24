(** Collider component for Eon Engine.

    Eon Engine provides collider data components but no built-in physics
    simulation. Collision detection and response are left to the user or an
    external physics library (e.g. Box2D via C bindings).

    Typical integration pattern:
    - Register [Collider] components on relevant entities.
    - In a user-defined system, query entities with [Collider] and drive an
      external physics engine with that data each frame.
    - Write collision results (contacts, velocities) back to ECS components
      (e.g. [Velocity]) via commands.
*)

(** Collision shape. *)
type shape =
  | Circle  of float          (** Radius. *)
  | Box     of float * float  (** Width, height. *)
  | Capsule of float * float  (** Radius, height. *)

type t = {
  shape      : shape;  (** Geometry used for collision detection. *)
  layer      : int;    (** Collision layer this collider belongs to. *)
  mask       : int;    (** Bitmask of layers this collider interacts with. *)
  is_trigger : bool;   (** If true, detects overlaps but does not resolve collisions. *)
  is_static  : bool;   (** If true, the collider is immovable (infinite mass). *)
}

val component : t Component_descriptor.t

val name : string

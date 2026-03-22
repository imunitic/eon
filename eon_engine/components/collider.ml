(** Collider component for Eon Engine. *)

open Component_descriptor

type shape =
  | Circle  of float          (** Radius. *)
  | Box     of float * float  (** Width, height. *)
  | Capsule of float * float  (** Radius, height. *)

type t = {
  shape      : shape;
  layer      : int;
  mask       : int;
  is_trigger : bool;
  is_static  : bool;
}

let component : t component_descriptor = component "Collider"

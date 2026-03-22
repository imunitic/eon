(** Rotation component (angle in radians) for Eon Engine. *)

open Component_descriptor

type t = {
  angle : float;
}

let component : t component_descriptor = component "Rotation"
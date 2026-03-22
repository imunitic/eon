(** Camera target component for Eon Engine. *)

open Component_descriptor

type t = {
  priority : int;
  offset_x : float;
  offset_y : float;
}

let component : t component_descriptor = component "CameraTarget"

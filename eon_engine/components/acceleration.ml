(** 2D acceleration component for Eon Engine. *)

open Component_descriptor

type t = {
  ax : float;
  ay : float;
}

let component : t component_descriptor = component "Acceleration"
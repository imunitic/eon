(** 2D velocity component for Eon Engine. *)

open Component_descriptor

type t = {
  dx : float;
  dy : float;
}

let component : t component_descriptor = component "Velocity"
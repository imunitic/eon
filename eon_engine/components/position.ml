(** 2D position component for Eon Engine. *)

open Component_descriptor

type t = {
  x : float;
  y : float;
}

let component : t component_descriptor = component "Position"
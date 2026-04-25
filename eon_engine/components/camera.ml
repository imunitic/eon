(** Camera component for Eon Engine. *)

open Component_descriptor

type t = {
  x          : float;
  y          : float;
  zoom       : float;
  viewport_w : float;
  viewport_h : float;
  rotation   : float;
}

let component : t component_descriptor = component "Camera"

let name = Component_descriptor.name component

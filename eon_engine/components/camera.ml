(** Camera component for Eon Engine. *)

open Component_descriptor

type t = {
  zoom       : float;
  viewport_w : float;
  viewport_h : float;
  near       : float;
  far        : float;
}

let component : t component_descriptor = component "Camera"

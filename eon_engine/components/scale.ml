(** 2D scale component for Eon Engine. *)

open Component_descriptor

type t = {
  x : float;
  y : float;
}

let component : t component_descriptor = component "Scale"

let name = Component_descriptor.name component
(** Input component for Eon Engine. *)

open Component_descriptor

type t = {
  move_x  : float;
  move_y  : float;
  actions : string list;
}

let component : t component_descriptor = component "Input"

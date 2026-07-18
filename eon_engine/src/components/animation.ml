(** Sprite animation component for Eon Engine. *)

open Component_descriptor

type t = {
  clip    : string;
  frame   : int;
  speed   : float;
  playing : bool;
}

let component : t component_descriptor = component "Animation"

let name = Component_descriptor.name component

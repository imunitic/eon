(** Mana component (magic/energy resource) for Eon Engine. *)

open Component_descriptor

type t = {
  current : int;
  max : int;
}

let component : t component_descriptor = component "Mana"
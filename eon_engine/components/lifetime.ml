(** Lifetime component for Eon Engine. *)

open Component_descriptor

type t = {
  remaining : float;
}

let component : t component_descriptor = component "Lifetime"

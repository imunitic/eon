(** Lifetime component for Eon Engine. *)

open Component_descriptor

type t = {
  ttl : float;
}

let component : t component_descriptor = component "Lifetime"

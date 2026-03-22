(** Team affiliation component for Eon Engine. *)

open Component_descriptor

type t = {
  id : int;
}

let component : t component_descriptor = component "Team"
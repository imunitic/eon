(** Health component for Eon Engine. *)

open Component_descriptor

type t = {
  current : int;
  max : int;
}

let component : t component_descriptor = component "Health"
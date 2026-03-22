(** Input component for Eon Engine. *)

open Component_descriptor

type t = {
  player_id : int;
}

let component : t component_descriptor = component "Input"

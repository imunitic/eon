(** Sprite rendering component for Eon Engine. *)

open Component_descriptor

type t = {
  texture_id : string;
  layer      : int;
  flip_x     : bool;
  flip_y     : bool;
}

let component : t component_descriptor = component "Sprite"

let name = Component_descriptor.name component

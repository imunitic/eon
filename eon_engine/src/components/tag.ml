(** Tag component for Eon Engine. *)

open Component_descriptor

type t = {
  value : string;
}

let component : t component_descriptor = component "Tag"

let name = Component_descriptor.name component

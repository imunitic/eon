(** Tag component for Eon Engine. *)

open Component_descriptor

type t = {
  name : string;
}

let component : t component_descriptor = component "Tag"

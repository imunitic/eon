(** Entity ownership component for Eon Engine. *)

open Component_descriptor

type t = {
  entity_id : Eon_ecs.Entity_id.t;
}

let component : t component_descriptor = component "Owner"
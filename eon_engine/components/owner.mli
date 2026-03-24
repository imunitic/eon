(** Entity ownership component for Eon Engine. *)

type t = {
  entity_id : Eon_ecs.Entity_id.t;
}

val component : t Component_descriptor.t

val name : string
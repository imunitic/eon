(** Payload types for hierarchy-related commands on the command bus. *)

type entity_id = Eon_ecs.Entity_id.t

type reparent = {
  entity     : entity_id;
  new_parent : entity_id option;
  (** [None] detaches the entity, making it a root. *)
}

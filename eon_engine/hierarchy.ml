type entity_id = Eon_ecs.Entity_id.t

type reparent = {
  entity     : entity_id;
  new_parent : entity_id option;
}

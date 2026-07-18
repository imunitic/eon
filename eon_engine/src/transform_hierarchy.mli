(** Payload types and helpers for transform hierarchy commands and setup. *)

type entity_id = Eon_ecs.Entity_id.t

type reparent = {
  entity     : entity_id;
  new_parent : entity_id option;
  (** [None] detaches the entity, making it a root. *)
}

val despawn_recursive :
  'perm World.t ->
  entity_id ->
  emit:([ `Destroy_entity of entity_id ] -> unit) ->
  unit
(** [despawn_recursive world entity ~emit] traverses the subtree rooted at
    [entity] depth-first and emits [`Destroy_entity] for each node, deepest
    nodes first. [entity] itself is emitted last.

    Call from a system [update] (tick phase, before drain). The emitted
    commands are queued and processed during drain — [Lifecycle_system] calls
    [World.destroy_entity] and [Transform_system] detaches any remaining
    children.

    Safe to call from a Parallel system: reads the world (no [rw] required)
    and calls [emit] once per node. *)

val attach :
  World.rw World.t ->
  parent:entity_id ->
  child:entity_id ->
  unit
(** [attach world ~parent ~child] synchronously sets [Parent] on [child] and
    prepends [child] to [parent]'s [Children] list.

    For world setup before the simulation loop starts. Mid-simulation hierarchy
    mutations must use the [`Reparent] command so [Transform_system] keeps
    [Parent] and [Children] consistent. *)

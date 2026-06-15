(** Pluggable backend signature for query execution.

    A backend's only job is to yield matching entity ids. Value extraction
    is the caller's responsibility via [View]. *)

module type S = sig
  type world
  (** Abstract world type — decouples backend from [Eon_ecs.World.t].
      A future archetype backend sets this to its own world type. *)

  val iter_entities :
    world ->
    required:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> unit) ->
    unit
  (** Yield every alive entity that has all [required] components and none of
      the [excludes] components. *)

  val count :
    world ->
    required:string list ->
    excludes:string list ->
    int
end

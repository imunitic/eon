(** Pluggable backend signature for query execution.

    A backend's only job is to yield matching entity ids. Value extraction
    is the caller's responsibility via [View]. *)

module type S = sig
  type 'perm world
  (** Abstract world type parameterised by capability — decouples backend from
      [Eon_ecs.World.t]. Read-only and read-write worlds both satisfy backends
      since query operations are reads only. *)

  val iter_entities :
    'perm world ->
    required:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> unit) ->
    unit
  (** Yield every alive entity that has all [required] components and none of
      the [excludes] components. *)

  val count :
    'perm world ->
    required:string list ->
    excludes:string list ->
    int
end

(** ECS system that processes [`Destroy_entity] commands.

    Calls [World.destroy_entity] for each [`Destroy_entity] command received,
    guarded by [World.is_alive] — duplicate commands for the same entity are safe.

    Register AFTER [Transform_system]: [Single_bus] dispatches in pipeline
    registration order (FIFO), so [Transform_system]'s handler fires first —
    detaching children before this system removes the entity.

    Use [Default.make] for the common case. Use [Make] when wiring a custom
    [DISPATCH] pipeline. *)

module Make (Sys : System.DISPATCH) : sig
  val make :
    ?on_command:(World.rw World.t -> ([> `Destroy_entity of Transform_hierarchy.entity_id ] as 'c) -> unit) ->
    unit ->
    (unit, unit, 'c) Sys.t
end

module Default : sig
  val make :
    ?on_command:(World.rw World.t -> ([> `Destroy_entity of Transform_hierarchy.entity_id ] as 'c) -> unit) ->
    unit ->
    (unit, unit, 'c) System.Default.t
end

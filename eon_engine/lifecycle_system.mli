(** ECS system that processes [`Destroy_entity] commands.

    Calls [World.destroy_entity] for each [`Destroy_entity] command received,
    guarded by [World.is_alive] — duplicate commands for the same entity are safe.

    Register BEFORE [Transform_system]: [Single_bus] is LIFO so first-registered
    fires last, giving this system finalizer semantics — [Transform_system] detaches
    children first, then this system removes the entity.

    Use [Default.make] for the common case. Use [Make] when wiring a custom
    [DISPATCH] pipeline. *)

module Make (Sys : System.DISPATCH) : sig
  val make : unit -> (unit, unit, [> `Destroy_entity of Hierarchy.entity_id ]) Sys.t
end

module Default : sig
  val make : unit -> (unit, unit, [> `Destroy_entity of Hierarchy.entity_id ]) System.Default.t
end

(** ECS system that maintains the transform hierarchy.

    - [update] (exclusive): DFS from root entities — propagates [World_transform]
      top-down so every entity's world-space transform is up to date.
    - [on_command (`Reparent)]: mutates [Parent] and [Children] consistently.
    - [on_command (`Destroy_entity)]: detaches children before the entity is removed
      (does NOT call [World.destroy_entity] — that is [Lifecycle_system]'s job).

    Register this system BEFORE [Lifecycle_system]: [Single_bus] dispatches in
    pipeline registration order (FIFO), so this system's handler fires first —
    detaching children before [Lifecycle_system] removes the entity.

    Use [Default.make] for the common case. Use [Make] when wiring a custom
    [DISPATCH] pipeline. *)

module Make (Sys : System.DISPATCH) : sig
  val make : unit -> (unit, unit, [> `Reparent of Hierarchy.reparent | `Destroy_entity of Hierarchy.entity_id ]) Sys.t
end

module Default : sig
  val make : unit -> (unit, unit, [> `Reparent of Hierarchy.reparent | `Destroy_entity of Hierarchy.entity_id ]) System.Default.t
end

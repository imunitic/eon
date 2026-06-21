(** Phantom capability wrapper around [World.t].

    Enforces read-only vs read-write access at compile time using phantom
    polymorphic-variant types. [Parallel] system updates receive [ro t] and
    cannot call write operations; [Exclusive] system updates receive [rw t]
    and can call any operation.

    [wrap] and [readonly] are zero-cost: both are single-field record
    allocations that hold the underlying [World.t]. No runtime checks occur.

    Limits: the phantom guards the [World] API boundary, not mutation
    reachable through it (e.g. mutable values stored as services). *)

(** Read-only capability. *)
type ro = [ `R ]

(** Read-write capability. *)
type rw = [ `R | `W ]

(** Capability-wrapped world. ['perm] is phantom. *)
type 'perm t

(** Wrap a core world with full read-write capability.
    Pipeline-internal; game code never calls this directly. *)
val wrap     : Eon_ecs.World.t -> rw t

(** Downgrade a read-write capability to read-only. Zero cost. *)
val readonly : rw t -> ro t

(** {2 Read operations — accept any capability} *)

val get_component        : _ t -> World.entity_id -> 'a Component_descriptor.t -> 'a option
val is_alive             : _ t -> World.entity_id -> bool
val count_entities       : _ t -> int
val is_registered        : _ t -> 'a Component_descriptor.t -> bool
val get_data             : _ t -> [> ] -> 'a option
val get_service          : _ t -> [> ] -> 'a option
val list_services        : _ t -> int list
val iter_entities        : _ t -> string list -> (World.entity_id -> unit) -> unit
val has_component        : _ t -> World.entity_id -> string -> bool

(** {2 Write operations — require [rw] capability} *)

val create_entity        : rw t -> World.entity_id
val destroy_entity       : rw t -> World.entity_id -> unit
val add_component        : rw t -> World.entity_id -> 'a Component_descriptor.t -> 'a -> unit
val set_component        : rw t -> World.entity_id -> 'a Component_descriptor.t -> 'a -> unit
val remove_component     : rw t -> World.entity_id -> 'a Component_descriptor.t -> unit
val remove_all_components: rw t -> World.entity_id -> unit
val register             : rw t -> 'a Component_descriptor.t -> Component_descriptor.registration_result
val add_data             : rw t -> [> ] -> 'a -> unit
val set_data             : rw t -> [> ] -> 'a -> unit
val add_service          : rw t -> [> ] -> 'a -> unit

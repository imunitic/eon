(** Re-export entity identifiers for convenience when working with the manager. *)
module Entity_id = Entity_id

(** Internal allocator for entity lifetimes and component storage. *)
type t

(** Create a manager with an initial capacity. *)
val create : int -> t

(** Current maximum number of entities that can be stored without growing. *)
val capacity : t -> int

(** Number of live entities. *)
val count : t -> int

(** Ensure capacity grows to fit more entities. *)
val grow : t -> unit

(** Allocate a new entity identifier. *)
val create_entity : t -> Entity_id.t

(** Destroy an entity and recycle its slot. *)
val destroy_entity : t -> Entity_id.t -> unit

(** Test whether an entity ID is alive. *)
val is_alive : t -> Entity_id.t -> bool

(** Inspect the generation stored at the given index. *)
val generation_at : t -> int -> int

(** Attach an initial component value to an entity. *)
val add_component : t -> Entity_id.t -> Component.any_component -> 'a -> unit

(** Overwrite an existing component value for an entity. *)
val set_component : t -> Entity_id.t -> Component.any_component -> 'a -> unit

(** Fetch an entity component, if present. *)
val get_component : t -> Entity_id.t -> Component.any_component -> 'a option

(** Remove a component from an entity. *)
val remove_component : t -> Entity_id.t -> Component.any_component -> unit

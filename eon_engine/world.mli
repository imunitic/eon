(** Eon Engine World wrapper.

    This module provides an opaque wrapper around [Eon_ecs.World.t] to
    decouple the public API from the underlying ECS implementation.
*)

(** Opaque handle to the engine world. *)
type t

(** Create a new empty world. *)
val create : unit -> t

(** Access the underlying ECS world.
    
    EXTENSION API: This function is exposed for backend implementors who need
    direct access to Eon_ecs.World.t. If you're building a game with eon_engine,
    you don't need this function. Use Eon_engine.Backend.World.to_raw instead.
*)
val to_raw : t -> Eon_ecs.World.t

(** Entity identifier type (re-exported from Eon_ecs). *)
type entity_id = Eon_ecs.Entity_id.t

(** Allocate a new entity inside the world. *)
val create_entity : t -> entity_id

(** Attach a component value to an entity.

    The component parameter uses the phantom-typed Component_descriptor.t for type safety.
    Internally, Component_descriptor.t is just a string, but the phantom type ensures
    that the value type matches the component's expected type.
*)
val add_component : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit

(** Overwrite the component value held by the entity. *)
val set_component : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit

(** Retrieve a component value, if the entity currently owns it. *)
val get_component : t -> entity_id -> 'a Component_descriptor.t -> 'a option

(** Remove a component from the entity. *)
val remove_component : t -> entity_id -> 'a Component_descriptor.t -> unit

(** Detach every component from the entity, typically during destruction. *)
val remove_all_components : t -> entity_id -> unit

(** Destroy the entity and detach all of its components. *)
val destroy_entity : t -> entity_id -> unit

(** Register a component descriptor with this world. *)
val register : t -> 'a Component_descriptor.t -> Component_descriptor.registration_result

(** Check if a component is registered in this world. *)
val is_registered : t -> 'a Component_descriptor.t -> bool

(** Count the number of currently alive entities. *)
val count_entities : t -> int

(** Check if an entity ID is currently alive. *)
val is_alive : t -> entity_id -> bool

(** {2 Data-plane store} *)

(** Attach arbitrary data, keyed by an open polymorphic variant, to the world.
    If data for the key already exists, it is overwritten. *)
val add_data : t -> [> ] -> 'a -> unit

(** Set (insert or overwrite) arbitrary data keyed by an open polymorphic variant.

    This is an alias for {!add_data} with naming that makes overwrite semantics explicit. *)
val set_data : t -> [> ] -> 'a -> unit

(** Retrieve data by key. Returns [None] if no data exists for the key. *)
val get_data : t -> [> ] -> 'a option

(** Number of stored data entries. *)
val count_data : t -> int

(** {2 Service-plane store} *)

(** Register a long-lived service (bus, singleton, etc.) accessible via variant key.
    If a service for the key already exists, it is overwritten. *)
val add_service : t -> [> ] -> 'a -> unit

(** Retrieve a previously registered service. Returns [None] if no service exists for the key. *)
val get_service : t -> [> ] -> 'a option

(** List the identifiers of all registered services.

    The returned integers are physical identities of variant constructors
    (derived via [Obj.repr]), usable only to count or check presence by
    comparing against the key's [Obj.repr] value. These are opaque identifiers
    with no guaranteed stability across runs. *)
val list_services : t -> int list

(** The Eon ECS world.

    [World] is the mutable runtime state shared by systems. It contains:
    - entity lifecycle state
    - component registry + component storages
    - resource stores for arbitrary data and long-lived services

    Basic usage:
    {[
      let world = World.create () in
      ignore (World.register_component world ~name:"Position" ~id:0);
      let e = World.create_entity world in
      World.add_component world e ~name:"Position" (0.0, 0.0)
    ]}
*)

(** Opaque handle to the world state. *)
type t

(** Create an empty world with no registered components or entities. *)
val create : unit -> t

(** Allocate a new entity inside the world. *)
val create_entity : t -> Entity_id.t

(** Destroy the entity and detach all of its components. *)
val destroy_entity : t -> Entity_id.t -> unit

(** Number of currently alive entities. *)
val count_entities : t -> int

(** Test whether the given entity ID is alive. *)
val is_alive : t -> Entity_id.t -> bool

(** Generation counter for the entity stored at the provided index. *)
val generation_at : t -> int -> int

(** Register a new component type, making it available to entities. *)
val register_component : t -> name:string -> id:int -> 'a Component.component

(** Lookup a registered component by name. *)
val find_component : t -> name:string -> 'a Component.component option

(** {2 Data-plane store} *)

(** Attach arbitrary data, keyed by an open polymorphic variant, to the world. *)
val add_data : t -> [> ] -> 'a -> unit

(** Set (insert or overwrite) arbitrary data keyed by an open polymorphic variant.

    This is an alias for {!add_data} with naming that makes overwrite semantics
    explicit. *)
val set_data : t -> [> ] -> 'a -> unit

(** Retrieve data by key. *)
val get_data : t -> [> ] -> 'a option

(** Number of stored data entries. *)
val count_data : t -> int

(** {2 Service-plane store} *)

(** Register a long-lived service (bus, singleton, etc.) accessible via variant key. *)
val add_service : t -> [> ] -> 'a -> unit

(** Retrieve a previously registered service. *)
val get_service : t -> [> ] -> 'a option

(** List the identifiers of all registered services. *)
val list_services : t -> int list

(** Attach a component value to an entity.

    Raises if the component name is not registered. *)
val add_component : t -> Entity_id.t -> name:string -> 'a -> unit

(** Overwrite the component value held by the entity.

    Raises if the component name is not registered. *)
val set_component : t -> Entity_id.t -> name:string -> 'a -> unit

(** Retrieve a component value, if the entity currently owns it.

    Returns [None] if the entity does not have the component.
    Raises if the component name is not registered. *)
val get_component : t -> Entity_id.t -> name:string -> 'a option

(** Remove a component from the entity.

    Raises if the component name is not registered. *)
val remove_component : t -> Entity_id.t -> name:string -> unit

(** Detach every component from the entity, typically during destruction. *)
val remove_all_components : t -> Entity_id.t -> unit

(** Monotonically increasing counter for the named component's sparse set,
    bumped on every add_component/remove_component that changes its
    membership (not on set_component of an already-present component,
    which changes a value but not membership).

    Raises if the component name is not registered, consistent with
    {!get_component}. *)
val component_generation : t -> string -> int

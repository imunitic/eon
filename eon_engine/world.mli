(** Eon Engine World wrapper. *)

(** Uniform world signature that all backends and engine code depend on.
    Has no reference to [Eon_ecs.World.t] — backends work with [W.t] throughout
    and call [W.iter_entities] / [W.has_component] for query operations. *)
module type S = sig
  type t

  val create               : unit -> t

  val create_entity        : t -> Eon_ecs.Entity_id.t
  val add_component        : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
  val set_component        : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
  val get_component        : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> 'a option
  val remove_component     : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> unit
  val remove_all_components: t -> Eon_ecs.Entity_id.t -> unit
  val destroy_entity       : t -> Eon_ecs.Entity_id.t -> unit
  val register             : t -> 'a Component_descriptor.t -> Component_descriptor.registration_result
  val is_registered        : t -> 'a Component_descriptor.t -> bool
  val count_entities       : t -> int
  val is_alive             : t -> Eon_ecs.Entity_id.t -> bool

  val add_data      : t -> [> ] -> 'a -> unit
  val set_data      : t -> [> ] -> 'a -> unit
  val get_data      : t -> [> ] -> 'a option
  val count_data    : t -> int
  val add_service   : t -> [> ] -> 'a -> unit
  val get_service   : t -> [> ] -> 'a option
  val list_services : t -> int list

  (** Backend query primitives — not for game code. *)

  val iter_entities : t -> string list -> (Eon_ecs.Entity_id.t -> unit) -> unit
  (** Iterate every alive entity that has all of the named components, using the
      smallest sparse set as the iteration base. Raises [Invalid_argument] if any
      name was never registered. *)

  val has_component : t -> Eon_ecs.Entity_id.t -> string -> bool
  (** Return [true] if the entity currently holds the named component.
      Returns [false] if the component is not registered or is absent on the entity.
      Used by backends to apply excludes post-filters by string name. *)
end

(** Opaque handle to the engine world. *)
type t

(** Create a new empty world. *)
val create : unit -> t

(** Access the underlying ECS world.

    EXTENSION API: Exposed for backend implementors who need direct access to
    [Eon_ecs.World.t]. Game code should not use this. *)
val to_raw : t -> Eon_ecs.World.t

(** Entity identifier type (re-exported from Eon_ecs). *)
type entity_id = Eon_ecs.Entity_id.t

val create_entity        : t -> entity_id
val add_component        : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
val set_component        : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
val get_component        : t -> entity_id -> 'a Component_descriptor.t -> 'a option
val remove_component     : t -> entity_id -> 'a Component_descriptor.t -> unit
val remove_all_components: t -> entity_id -> unit
val destroy_entity       : t -> entity_id -> unit
val register             : t -> 'a Component_descriptor.t -> Component_descriptor.registration_result
val is_registered        : t -> 'a Component_descriptor.t -> bool
val count_entities       : t -> int
val is_alive             : t -> entity_id -> bool

val add_data      : t -> [> ] -> 'a -> unit
val set_data      : t -> [> ] -> 'a -> unit
val get_data      : t -> [> ] -> 'a option
val count_data    : t -> int
val add_service   : t -> [> ] -> 'a -> unit
val get_service   : t -> [> ] -> 'a option
val list_services : t -> int list

val iter_entities : t -> string list -> (entity_id -> unit) -> unit
val has_component : t -> entity_id -> string -> bool

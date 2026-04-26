(** Engine World wrapper
    Provides higher-level API on top of Eon_ecs.World with automatic
    component registration and convenient access to entity operations.
*)

type t

(** {1 Construction} *)

val create : unit -> t
(** Create a new world instance *)

val to_raw : t -> Eon_ecs.World.t
(** Access the underlying ECS world (for backend implementations) *)

(** {1 Entity Operations} *)

val create_entity : t -> Eon_ecs.Entity_id.t
val destroy_entity : t -> Eon_ecs.Entity_id.t -> unit
val is_alive : t -> Eon_ecs.Entity_id.t -> bool

(** {1 Component Operations} *)

val register : t -> 'a Component_descriptor.t -> unit
(** Register a component descriptor with auto-generated ID *)

val add_component : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
val get_component : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> 'a option
val set_component : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
val remove_component : t -> Eon_ecs.Entity_id.t -> 'a Component_descriptor.t -> unit

(** {1 Service Operations} *)

val add_service : t -> [> ] -> 'a -> unit
val get_service : t -> [> ] -> 'a option

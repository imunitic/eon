(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

(** Query backend signature for pluggable query execution. *)
module Query_backend = Query_backend

(** Default sparse set backend. *)
module Sparse_set_backend = Sparse_set_backend

(** Query builder for efficient entity iteration. *)
module Query = Query

(** Module-based component registration API. *)
module Components = Components

(** Entity identifier type. *)
type entity_id = Eon_ecs.Entity_id.t

(** Engine world wrapper.
    
    Note: to_raw is NOT included in the public World API. Use Backend.World.to_raw
    if you're implementing a custom backend.
*)
module World : sig
  type t = World.t

  val create : unit -> t
  val create_entity : t -> entity_id
  val add_component : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val set_component : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val get_component : t -> entity_id -> 'a Component_descriptor.t -> 'a option
  val remove_component : t -> entity_id -> 'a Component_descriptor.t -> unit
  val remove_all_components : t -> entity_id -> unit
  val destroy_entity : t -> entity_id -> unit
  val register : t -> 'a Component_descriptor.t -> Components.registration_result
  val is_registered : t -> 'a Component_descriptor.t -> bool
  val count_entities : t -> int
  val is_alive : t -> entity_id -> bool
end

(** Extension API for backend implementors.
    
    This module provides the API surface for implementing custom backends
    and extensions to Eon Engine. If you're building a game with eon_engine,
    you don't need this module.
*)
module Backend : sig
  module World : sig
    val to_raw : World.t -> Eon_ecs.World.t
  end
end

(** Create a component descriptor with a given name.

    This is a convenience alias for [Components.component].
    
    Example:
    {[
      module Position = struct
        type t = { x : float; y : float }
        let component = Engine.component "Position"
      end
    ]}
*)
val component : string -> 'a Components.t

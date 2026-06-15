(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

(** Query backend signature for pluggable query execution. *)
module Query_backend = Query_backend

(** Default sparse set backend. Provides [Make(W : World.S)] functor and [Default]
    instance backed by [World.t]. *)
module Sparse_set_backend = Sparse_set_backend

(** Query builder for efficient entity iteration. *)
module Query = Query

(** Module-based component registration API. *)
module Components = Components

(** Entity identifier type. *)
type entity_id = Eon_ecs.Entity_id.t

(** Engine world wrapper. *)
module World : sig
  (** Uniform world signature — program backends and engine utilities against this,
      not against the concrete [t] directly. *)
  module type S = World.S

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

  (** {2 Data-plane store} *)

  val add_data : t -> [> ] -> 'a -> unit
  val set_data : t -> [> ] -> 'a -> unit
  val get_data : t -> [> ] -> 'a option
  val count_data : t -> int

  (** {2 Service-plane store} *)

  val add_service : t -> [> ] -> 'a -> unit
  val get_service : t -> [> ] -> 'a option
  val list_services : t -> int list

  (** {2 Backend query primitives} *)

  val iter_entities : t -> string list -> (entity_id -> unit) -> unit
  val has_component : t -> entity_id -> string -> bool
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

    Example:
    {[
      module Position = struct
        type t = { x : float; y : float }
        let component = Engine.component "Position"
      end
    ]}
*)
val component : string -> 'a Components.t

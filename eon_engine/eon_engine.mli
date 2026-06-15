(** Eon Engine public API. *)

module Query_backend = Query_backend

module Sparse_set_backend = Sparse_set_backend

module Query = Query

module View = View

module Components = Components

type entity_id = Eon_ecs.Entity_id.t

module World : sig
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

  val add_data : t -> [> ] -> 'a -> unit
  val set_data : t -> [> ] -> 'a -> unit
  val get_data : t -> [> ] -> 'a option
  val count_data : t -> int
  val add_service : t -> [> ] -> 'a -> unit
  val get_service : t -> [> ] -> 'a option
  val list_services : t -> int list

  val iter_entities : t -> string list -> (entity_id -> unit) -> unit
  val has_component : t -> entity_id -> string -> bool
end

module Backend : sig
  module World : sig
    val to_raw : World.t -> Eon_ecs.World.t
  end
end

val component : string -> 'a Components.t

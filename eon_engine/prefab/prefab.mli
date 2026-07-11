[@@@warning "-67"]

(** Generic prefab loading: load a named entity definition from some data
    source, get back a live entity with all its components attached.

    Format-agnostic — [raw_data] is an associated type, resolved per
    functor instantiation, not one shared runtime representation. See
    {!Prefab_edn} for the EDN-backed instantiation shipped by [eon_engine]. *)

type entity_id = Eon_ecs.Entity_id.t

(** Where the data comes from. *)
module type Source = sig
  type raw_data
  val load : string -> raw_data
  (** [load name] returns the raw data for the named prefab. Raises if not
      found — resolution failure is not part of the control flow. *)
end

(** How a single component gets deserialized from a sub-tree of raw data. *)
module type Component_deserializer = sig
  type raw_data
  val deserialize : World.rw World.t -> entity_id -> key:string -> raw_data -> unit
  (** Must call {!World.set_component} (not [add_component]) so the same
      deserializer works for both a fresh spawn and, later, a hot-reload
      re-run against an existing entity. *)
end

(** How to decompose a [raw_data] document into the pieces the loader
    needs: an optional inheritance parent, the named components, and any
    nested children. Format-specific — an EDN document walks
    [VMap]/[VKeyword], a hypothetical protobuf source would decompose its
    own message shape (or supply a trivial [merge] with no real
    inheritance support). *)
module type Document_shape = sig
  type raw_data
  val extends_of : raw_data -> string option
  val components_of : raw_data -> (string * raw_data) list
  val children_of : raw_data -> raw_data list
  val merge : raw_data -> raw_data -> raw_data
  (** [merge base override] — [override]'s values win; how deep the merge
      goes (if at all) is up to the implementation. *)
end

module Make (Source : Source) (Doc : Document_shape with type raw_data = Source.raw_data) : sig
  val register_component :
    string -> (module Component_deserializer with type raw_data = Source.raw_data) -> unit
  (** Registers the deserializer to invoke for a given key in a prefab's
      [:components] map. Last registration for a key wins (plain
      [Hashtbl.replace] — see the design doc for why this is
      per-instantiation module state, not a [Service.S]). *)

  val load : World.rw World.t -> string -> entity_id
  (** [load world name] resolves [name]'s [:extends] chain (raising on a
      cycle), spawns the resulting entity tree via a tail-recursive
      work-list (stack depth independent of hierarchy depth), and returns
      the root entity. Raises if a [:components] key has no registered
      deserializer. *)
end

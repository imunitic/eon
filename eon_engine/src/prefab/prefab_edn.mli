[@@@warning "-67"]

(** [eon_engine]'s pre-built EDN instantiation of {!Prefab.Make} — the
    "out of the box" path: EDN loading with no parsing code required.
    Not the only possible instantiation; a game wanting a different
    format instantiates {!Prefab.Make} with its own [Source]/
    [Document_shape] pair. *)

module Make (Root : sig
  val path : string
end) : sig
  val register_component :
    string
    -> (module Prefab.Component_deserializer with type raw_data = Eon_edn.Edn_effects.value)
    -> unit

  val load : World.rw World.t -> string -> Prefab.entity_id
end

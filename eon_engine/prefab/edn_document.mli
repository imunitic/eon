(** {!Prefab.Document_shape} for {!Eon_edn.Edn_effects.value} — the
    EDN document conventions: [:extends] for inheritance, [:components]
    for the per-key deserializer dispatch map, [:children] for nested
    entities. *)

type raw_data = Eon_edn.Edn_effects.value

val extends_of : raw_data -> string option
val components_of : raw_data -> (string * raw_data) list
val children_of : raw_data -> raw_data list
val merge : raw_data -> raw_data -> raw_data
(** Deep-merges [VMap]s recursively (a key present in both sides merges
    field-by-field, [override]'s scalar values win); everything else is a
    flat replace. *)

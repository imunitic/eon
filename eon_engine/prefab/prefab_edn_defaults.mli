(** Opt-in default {!Prefab.Component_deserializer}s for the engine's
    genuinely prefab-authorable components: [Velocity], [Local_transform],
    [Collider], [Sprite], [Animation], [Camera], [Tag].

    Deliberately excludes [Parent]/[Children]/[World_transform] — those
    are managed by {!Transform_hierarchy}/{!Transform_system} (set via
    [attach]/[propagate]), not authored prefab data.

    Not auto-registered anywhere — a game calls {!register_all} once at
    startup if it wants these, passing its own [Prefab_edn.Make(Root)]
    instantiation's [register_component]. *)

val register_all :
  (string
   -> (module Prefab.Component_deserializer with type raw_data = Eon_edn.Edn_effects.value)
   -> unit)
  -> unit

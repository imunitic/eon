type ro = [ `R ]
type rw = [ `R | `W ]
type 'perm t = { world : World.t }

let wrap world   = { world }
let readonly t   = { world = t.world }

(* Read operations — delegate to Eon_engine.World *)
let get_component t entity comp      = World.get_component t.world entity comp
let is_alive t                       = World.is_alive t.world
let count_entities t                 = World.count_entities t.world
let is_registered t comp             = World.is_registered t.world comp
let get_data t                       = World.get_data t.world
let get_service t                    = World.get_service t.world
let list_services t                  = World.list_services t.world
let iter_entities t                  = World.iter_entities t.world
let has_component t entity comp      = World.has_component t.world entity (Component_descriptor.name comp)

(* Write operations — delegate to Eon_engine.World *)
let create_entity t                  = World.create_entity t.world
let destroy_entity t                 = World.destroy_entity t.world
let add_component t entity comp v    = World.add_component t.world entity comp v
let set_component t entity comp v    = World.set_component t.world entity comp v
let remove_component t entity comp   = World.remove_component t.world entity comp
let remove_all_components t          = World.remove_all_components t.world
let register t comp                  = World.register t.world comp
let add_data t                       = World.add_data t.world
let set_data t                       = World.set_data t.world
let add_service t                    = World.add_service t.world

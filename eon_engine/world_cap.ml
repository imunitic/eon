type ro = [ `R ]
type rw = [ `R | `W ]
type 'perm t = { raw : World.t }

let wrap world    = { raw = world }
let readonly t    = { raw = t.raw }

let get_component t         = World.get_component t.raw
let is_alive t              = World.is_alive t.raw
let count_entities t        = World.count_entities t.raw
let is_registered t         = World.is_registered t.raw
let get_data t              = World.get_data t.raw
let get_service t           = World.get_service t.raw
let list_services t         = World.list_services t.raw
let iter_entities t         = World.iter_entities t.raw
let has_component t         = World.has_component t.raw

let create_entity t         = World.create_entity t.raw
let destroy_entity t        = World.destroy_entity t.raw
let add_component t         = World.add_component t.raw
let set_component t         = World.set_component t.raw
let remove_component t      = World.remove_component t.raw
let remove_all_components t = World.remove_all_components t.raw
let register t              = World.register t.raw
let add_data t              = World.add_data t.raw
let set_data t              = World.set_data t.raw
let add_service t           = World.add_service t.raw

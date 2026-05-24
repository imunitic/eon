(** Eon Engine World wrapper implementation. *)

type t = {
  raw : Eon_ecs.World.t
}

type entity_id = Eon_ecs.Entity_id.t

let create () =
  { raw = Eon_ecs.World.create () }

let to_raw world =
  world.raw

let create_entity world =
  Eon_ecs.World.create_entity world.raw

let add_component world entity component value =
  let name = Component_descriptor.name component in
  Eon_ecs.World.add_component world.raw entity ~name value

let set_component world entity component value =
  let name = Component_descriptor.name component in
  Eon_ecs.World.set_component world.raw entity ~name value

let get_component world entity component =
  let name = Component_descriptor.name component in
  Eon_ecs.World.get_component world.raw entity ~name

let remove_component world entity component =
  let name = Component_descriptor.name component in
  Eon_ecs.World.remove_component world.raw entity ~name

let remove_all_components world entity =
  Eon_ecs.World.remove_all_components world.raw entity

let destroy_entity world entity =
  Eon_ecs.World.destroy_entity world.raw entity

let register world comp =
  Component_descriptor.register world.raw comp

let is_registered world comp =
  Component_descriptor.is_registered world.raw comp

let count_entities world =
  Eon_ecs.World.count_entities world.raw

let is_alive world entity =
  Eon_ecs.World.is_alive world.raw entity

let add_data world key value =
  Eon_ecs.World.add_data world.raw key value

let set_data world key value =
  Eon_ecs.World.set_data world.raw key value

let get_data world key =
  Eon_ecs.World.get_data world.raw key

let count_data world =
  Eon_ecs.World.count_data world.raw

let add_service world key value =
  Eon_ecs.World.add_service world.raw key value

let get_service world key =
  Eon_ecs.World.get_service world.raw key

let list_services world =
  Eon_ecs.World.list_services world.raw

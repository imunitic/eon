type t = {
  world  : World.t;
  entity : Eon_ecs.Entity_id.t;
}

let entity v = v.entity

let get v comp =
  match World.get_component v.world v.entity comp with
  | Some x -> x
  | None ->
    invalid_arg ("View.get: component absent: " ^ Component_descriptor.name comp)

let get_opt v comp =
  World.get_component v.world v.entity comp

let make world entity = { world; entity }

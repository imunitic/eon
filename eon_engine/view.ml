type t = {
  world  : World.ro World.t;
  entity : Eon_ecs.Entity_id.t;
}

let entity v = v.entity

let get v (module M : Component.S) =
  match (World.get_component v.world v.entity M.component : M.t option) with
  | Some x -> x
  | None ->
    invalid_arg ("View.get: component absent: " ^ Component_descriptor.name M.component)

let get_opt v (module M : Component.S) =
  (World.get_component v.world v.entity M.component : M.t option)

let make world entity = { world = World.as_ro world; entity }

open Component_descriptor

type t = { entities : Eon_ecs.Entity_id.t list }

let component : t component_descriptor = component "Children"

let name = Component_descriptor.name component

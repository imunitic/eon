open Component_descriptor

type t = { entity : Eon_ecs.Entity_id.t }

let component : t component_descriptor = component "Parent"

let name = Component_descriptor.name component

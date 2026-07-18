open Component_descriptor

type t = {
  position : Math.Vec2.t;
  rotation : float;
  scale    : Math.Vec2.t;
}

let component : t component_descriptor = component "Local_transform"

let name = Component_descriptor.name component

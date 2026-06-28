open Component_descriptor

type t = {
  zoom     : float option;
  rotation : float option;
  viewport : (float * float * float * float) option;
}

let component : t component_descriptor = component "Camera"

let name = Component_descriptor.name component

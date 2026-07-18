type 'a t = string

type 'a component_descriptor = 'a t

type registration_result =
  | Registered
  | Already_registered

let component name : 'a t =
  name

let name (comp : 'a t) : string =
  comp

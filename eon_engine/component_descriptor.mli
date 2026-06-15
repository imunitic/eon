type 'a t = string

type 'a component_descriptor = 'a t

type registration_result =
  | Registered
  | Already_registered

val component : string -> 'a t

val name : 'a t -> string

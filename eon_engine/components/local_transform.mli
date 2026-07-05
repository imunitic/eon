type t = {
  position : Math.Vec2.t;
  rotation : float;
  scale    : Math.Vec2.t;
}

val component : t Component_descriptor.t

val name : string

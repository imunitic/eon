(** Rotation component (angle in radians) for Eon Engine. *)

type t = {
  angle : float;
}

val component : t Component_descriptor.t
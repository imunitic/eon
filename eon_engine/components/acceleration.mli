(** 2D acceleration component for Eon Engine. *)

type t = {
  ax : float;
  ay : float;
}

val component : t Component_descriptor.t

val name : string
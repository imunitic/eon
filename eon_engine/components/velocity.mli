(** 2D velocity component for Eon Engine. *)

type t = {
  dx : float;
  dy : float;
}

val component : t Component_descriptor.t
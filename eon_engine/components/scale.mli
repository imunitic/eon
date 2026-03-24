(** 2D scale component for Eon Engine. *)

type t = {
  x : float;
  y : float;
}

val component : t Component_descriptor.t

val name : string
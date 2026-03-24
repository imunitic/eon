(** Mana component (magic/energy resource) for Eon Engine. *)

type t = {
  current : int;
  max : int;
}

val component : t Component_descriptor.t

val name : string
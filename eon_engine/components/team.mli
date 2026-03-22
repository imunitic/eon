(** Team affiliation component for Eon Engine. *)

type t = {
  id : int;
}

val component : t Component_descriptor.t
(** Camera target component for Eon Engine. *)

type t = {
  priority : int;    (** Higher priority targets take precedence when multiple exist. *)
  offset_x : float;  (** Horizontal offset from the entity position. *)
  offset_y : float;  (** Vertical offset from the entity position. *)
}

val component : t Component_descriptor.t

val name : string

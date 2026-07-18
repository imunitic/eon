(** Sprite rendering component for Eon Engine. *)

type t = {
  texture_id : string;  (** Asset identifier for the texture to render. *)
  layer      : int;     (** Draw order; higher values render on top. *)
  flip_x     : bool;    (** Mirror the sprite horizontally. *)
  flip_y     : bool;    (** Mirror the sprite vertically. *)
}

val component : t Component_descriptor.t

val name : string

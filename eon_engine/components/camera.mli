(** Camera component for Eon Engine. *)

type t = {
  zoom       : float;  (** Zoom factor; 1.0 is default, >1.0 zooms in. *)
  viewport_w : float;  (** Viewport width in world units. *)
  viewport_h : float;  (** Viewport height in world units. *)
  near       : float;  (** Near clipping plane (z-depth). *)
  far        : float;  (** Far clipping plane (z-depth). *)
}

val component : t Component_descriptor.t

val name : string

(** Camera component for Eon Engine.

    A self-contained description of a viewport positioned in the world.
    Multiple cameras are supported — attach this component to any entity.
    Camera follow, shake, and other behaviours are implemented as regular
    systems that update these fields each frame.
*)

type t = {
  x          : float;  (** World-space X position of the camera. *)
  y          : float;  (** World-space Y position of the camera. *)
  zoom       : float;  (** Zoom factor; 1.0 is default, >1.0 zooms in. *)
  viewport_w : float;  (** Viewport width in world units. *)
  viewport_h : float;  (** Viewport height in world units. *)
  rotation   : float;  (** Camera rotation in radians. *)
}

val component : t Component_descriptor.t

val name : string

(** Camera component for Eon Engine.

    Attach to any entity that also has a [Position] component. The collector
    reads [Position] for world-space location and [Camera] for the remaining
    parameters, then emits a [`Set_camera] command into the render graph.

    Multiple cameras are supported — a minimap camera and a main camera are
    simply two entities with [Camera] components, each with a different
    [viewport].

    Camera follow is modelled by a separate [Camera_target] component on the
    camera entity; the collector resolves the target entity's [Position] and
    passes it as the [target] field of [`Set_camera].
*)

type t = {
  zoom     : float option;  (** Zoom factor; None = 1.0 (default). >1.0 zooms in. *)
  rotation : float option;  (** Rotation in radians; None = 0.0. *)
  viewport : (float * float * float * float) option;
  (** Screen-space destination rect [(x, y, w, h)].
      None   = full screen (main camera).
      Some r = render into this rect — use for minimap or split-screen. *)
}

val component : t Component_descriptor.t

val name : string

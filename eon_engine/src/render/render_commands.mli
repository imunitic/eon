(** Backend-agnostic 2D render command set.

    Commands are emitted by collectors into a {!Render_stream.t} and consumed
    by a {!Rendering_backend.S} implementation. The stream is ordered and
    deterministic — backends may process it directly or preprocess it into a
    render graph, batches, or GPU command buffers as they see fit.

    Backends extend the base set via polymorphic variant inclusion:
    {[
      type command = [
        | Render_commands.command
        | `Apply_shader   of shader
        | `Draw_particles of particle_system
      ]
    ]} *)

type camera = {
  position : float * float;  (** World-space camera centre. *)
  zoom     : float option;   (** Zoom factor; [None] = 1.0. *)
  rotation : float option;   (** Radians; [None] = 0.0. *)
  target   : (float * float) option;
  (** World-space point the camera tracks. [None] = free camera. *)
  viewport : Math.Rect.t option;
  (** Screen-space region to render into. [None] = full screen. *)
}

type texture = {
  texture_id : string;
  source     : Math.Rect.t option;
  (** Source region within the texture. [None] = full texture.
      Use for sprite sheet frames. *)
  dest       : Math.Rect.t;    (** Destination rect in world space. *)
  rotation   : float option;   (** Radians; [None] = 0.0. *)
  origin     : (float * float) option;
  (** Rotation pivot in [dest]-local coordinates. [None] = top-left. *)
  tint       : Color.t option;
  (** Colour multiply — use for hit flash, transparency, team tints.
      [None] = white (no tint). *)
  layer      : int;
}

type text = {
  text     : string;
  position : float * float;  (** Top-left corner in world space. *)
  font_id  : string;
  size     : float;          (** Font size in world units. *)
  color    : Color.t;
  layer    : int;
}

type rect_cmd = {
  rect   : Math.Rect.t;
  color  : Color.t;
  filled : bool;  (** [true] = filled; [false] = outline. *)
  layer  : int;
}

type circle = {
  center : float * float;
  radius : float;
  color  : Color.t;
  filled : bool;
  layer  : int;
}

type line = {
  start     : float * float;
  stop      : float * float;
  thickness : float;
  color     : Color.t;
  layer     : int;
}

type command = [
  | `Clear_background of Color.t
  (** Fill the entire framebuffer before any draw calls. *)
  | `Set_camera   of camera
  (** Establish a camera context. All world-space draw commands that follow
      (until the next [`Set_camera]) are rendered relative to this camera. *)
  | `Draw_texture of texture
  (** Draw a texture or sprite-sheet frame. *)
  | `Draw_text    of text
  | `Draw_rect    of rect_cmd
  | `Draw_circle  of circle
  | `Draw_line    of line
]

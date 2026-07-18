(** Sprite animation component for Eon Engine. *)

type t = {
  clip    : string;  (** Name of the active animation clip. *)
  frame   : int;     (** Current frame index within the clip. *)
  speed   : float;   (** Playback speed multiplier. *)
  playing : bool;    (** Whether the animation is currently playing. *)
}

val component : t Component_descriptor.t

val name : string

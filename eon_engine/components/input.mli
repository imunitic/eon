(** Input component for Eon Engine.

    Carries the player's movement intent and active actions for the current
    frame. This component holds resolved intent, not raw hardware state.

    {b Pipeline usage:}
    - An input system runs in the input phase (before the gameplay phase).
      It reads raw platform state (keyboard, gamepad) from a world resource
      and writes the derived intent into this component.
    - Gameplay systems run in the gameplay phase and read [Input] to apply
      behavior (e.g. set [Velocity] from [move_x]/[move_y], trigger animations
      from [actions]).

    This separation keeps gameplay systems platform-agnostic and testable
    without a real input device.
*)

type t = {
  move_x  : float;        (** Horizontal movement axis, range [-1.0, 1.0]. *)
  move_y  : float;        (** Vertical movement axis, range [-1.0, 1.0]. *)
  actions : string list;  (** Active action names this frame (e.g. ["jump"; "attack"]). *)
}

val component : t Component_descriptor.t

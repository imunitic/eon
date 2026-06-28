(** Immutable snapshot of raw input state for one frame.

    Produced by [Input_backend.S.collect] and written into the world data
    plane by the engine loop before [Buses.collect] runs. Game code reads it
    via [get]; the engine loop writes it via [set].

    Backend correctness requirements:
    - [keys_pressed] / [keys_released]: true leading/trailing edge only —
      OS key-repeat events must be suppressed.
    - On window focus loss: clear [keys_down] and synthesize releases for
      every key that was held.
    - Gamepad sticks: apply circular dead zone before normalising to [-1..1].
    - [text_input]: populate from OS/IME text event, not reconstructed from
      key codes. [None] when no text was typed this frame.
    - Poll-based backends leave [events = []]. *)

type modifiers = {
  shift : bool;
  ctrl  : bool;
  alt   : bool;
  meta  : bool;
}

type input_event =
  | Key_down     of Key.t            * float  (** normalised 0.0–1.0 within frame *)
  | Key_up       of Key.t            * float
  | Mouse_down   of Mouse_button.t   * float
  | Mouse_up     of Mouse_button.t   * float
  | Gamepad_down of Gamepad_button.t * float
  | Gamepad_up   of Gamepad_button.t * float

type gamepad_state = {
  left_stick       : float * float;          (** normalised, dead-zone applied *)
  right_stick      : float * float;
  buttons_down     : Gamepad_button.Set.t;
  buttons_pressed  : Gamepad_button.Set.t;
  buttons_released : Gamepad_button.Set.t;
  triggers         : float * float;          (** left, right — 0.0..1.0 *)
}

type t = {
  keys_down              : Key.Set.t;
  keys_pressed           : Key.Set.t;
  keys_released          : Key.Set.t;
  modifiers              : modifiers;
  mouse_screen           : int * int;
  mouse_delta            : int * int;
  mouse_buttons_down     : Mouse_button.Set.t;
  mouse_buttons_pressed  : Mouse_button.Set.t;
  mouse_buttons_released : Mouse_button.Set.t;
  scroll_delta           : float;
  text_input             : string option;
  gamepad                : gamepad_state option;
  events                 : input_event list;
}

(** All sets empty, no gamepad, no text, all deltas zero. *)
val empty : t

(** Read the current frame from the world data plane.
    Returns [None] before the first tick. *)
val get : 'perm World.t -> t option

(** Write a frame into the world data plane.
    Called by the engine loop; game code should not call this directly. *)
val set : World.rw World.t -> t -> unit

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
    - Poll-based backends leave [events = []].
    - Touch: a touch is any finger or pen/stylus contact with the screen.
      Hover without contact is not a touch. Each contact keeps one stable
      [Touch_id.t] from landing to lift, and game code need not tell finger
      from pen.
    - [touches_pressed] / [touches_released]: true edges only. A touch id is
      in at most one of [touches_released] / [touches_cancelled] per frame,
      and never in [touches_down] once released or cancelled.
    - Every id in [touches_pressed] is also in [touches_down] that frame. A
      contact that lands and lifts (or is cancelled) within one frame is
      reported pressed and down in that frame, and released or cancelled in
      the next, so no tap is lost. [events] may still carry the true
      [Touch_down] / [Touch_up] order and times.
    - On app backgrounding or window focus loss: report every held touch in
      [touches_cancelled] and clear [touches_down].
    - The backend does not synthesize mouse events from touch. *)

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
  | Touch_down   of Touch_id.t * (float * float) * float  (** id, position, frame time *)
  | Touch_move   of Touch_id.t * (float * float) * float
  | Touch_up     of Touch_id.t * (float * float) * float
  | Touch_cancel of Touch_id.t * (float * float) * float

(** State of one touch contact (finger or pen). The engine only carries
    these values; sourcing them is the backend's job. *)
type touch = {
  position : float * float;  (** same coordinate space as [mouse_screen], sub-pixel *)
  delta    : float * float;  (** movement since previous frame; [(0., 0.)] on first frame *)
  pressure : float;          (** 0.0..1.0; [1.0] when the backend has no pressure *)
  radius   : float;          (** contact radius in the units of [position]; [0.0] if unavailable *)
}

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
  touches_down           : touch Touch_id.Map.t;
      (** every contact currently on the screen *)
  touches_pressed        : Touch_id.Set.t;
      (** contacts that landed this frame; always present in [touches_down] *)
  touches_released       : touch Touch_id.Map.t;
      (** contacts lifted this frame, with their final state *)
  touches_cancelled      : touch Touch_id.Map.t;
      (** contacts aborted by the OS this frame, with their final state *)
  events                 : input_event list;
}

(** All sets and maps empty, no gamepad, no text, no touches, all deltas zero. *)
val empty : t

(** Read the current frame from the world data plane.
    Raises [Not_found] before the first tick — absent frame is a programming error. *)
val fetch : [> World.ro] World.t -> t

(** Read the current frame, returning [None] before the first tick. *)
val fetch_opt : [> World.ro] World.t -> t option

(** Write a frame into the world data plane.
    Called by the engine loop; game code should not call this directly. *)
val store : World.rw World.t -> t -> unit

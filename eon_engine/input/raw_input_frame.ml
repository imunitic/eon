type modifiers = {
  shift : bool;
  ctrl  : bool;
  alt   : bool;
  meta  : bool;
}

type input_event =
  | Key_down     of Key.t            * float
  | Key_up       of Key.t            * float
  | Mouse_down   of Mouse_button.t   * float
  | Mouse_up     of Mouse_button.t   * float
  | Gamepad_down of Gamepad_button.t * float
  | Gamepad_up   of Gamepad_button.t * float

type gamepad_state = {
  left_stick       : float * float;
  right_stick      : float * float;
  buttons_down     : Gamepad_button.Set.t;
  buttons_pressed  : Gamepad_button.Set.t;
  buttons_released : Gamepad_button.Set.t;
  triggers         : float * float;
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

let empty = {
  keys_down              = Key.Set.empty;
  keys_pressed           = Key.Set.empty;
  keys_released          = Key.Set.empty;
  modifiers              = { shift = false; ctrl = false; alt = false; meta = false };
  mouse_screen           = (0, 0);
  mouse_delta            = (0, 0);
  mouse_buttons_down     = Mouse_button.Set.empty;
  mouse_buttons_pressed  = Mouse_button.Set.empty;
  mouse_buttons_released = Mouse_button.Set.empty;
  scroll_delta           = 0.0;
  text_input             = None;
  gamepad                = None;
  events                 = [];
}

let resource_key = `Raw_input_frame

let get world  = World.get_data world resource_key
let set world frame = World.set_data world resource_key frame

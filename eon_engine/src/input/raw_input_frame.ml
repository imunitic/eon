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
  | Touch_down   of Touch_id.t * (float * float) * float
  | Touch_move   of Touch_id.t * (float * float) * float
  | Touch_up     of Touch_id.t * (float * float) * float
  | Touch_cancel of Touch_id.t * (float * float) * float

type touch = {
  position : float * float;
  delta    : float * float;
  pressure : float;
  radius   : float;
}

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
  touches_down           : touch Touch_id.Map.t;
  touches_pressed        : Touch_id.Set.t;
  touches_released       : touch Touch_id.Map.t;
  touches_cancelled      : touch Touch_id.Map.t;
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
  touches_down           = Touch_id.Map.empty;
  touches_pressed        = Touch_id.Set.empty;
  touches_released       = Touch_id.Map.empty;
  touches_cancelled      = Touch_id.Map.empty;
  events                 = [];
}

let resource_key = `Raw_input_frame

let fetch world =
  match World.get_data world resource_key with
  | Some f -> f
  | None   -> raise Not_found

let fetch_opt world = World.get_data world resource_key

let store world frame = World.set_data world resource_key frame

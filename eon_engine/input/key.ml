type t =
  | A | B | C | D | E | F | G | H | I | J | K | L | M
  | N | O | P | Q | R | S | T | U | V | W | X | Y | Z
  | Digit_0 | Digit_1 | Digit_2 | Digit_3 | Digit_4
  | Digit_5 | Digit_6 | Digit_7 | Digit_8 | Digit_9
  | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 | F10 | F11 | F12
  | Left | Right | Up | Down
  | Space | Enter | Escape | Tab | Backspace | Delete
  | Left_shift | Right_shift | Left_ctrl | Right_ctrl
  | Left_alt | Right_alt | Left_meta | Right_meta
  | Left_bracket | Right_bracket | Semicolon | Apostrophe
  | Comma | Period | Slash | Backslash | Grave | Minus | Equal
  | Home | End | Page_up | Page_down | Insert
  | Num_0 | Num_1 | Num_2 | Num_3 | Num_4
  | Num_5 | Num_6 | Num_7 | Num_8 | Num_9
  | Unknown

module Set = Set.Make (struct
  type nonrec t = t

  let compare = compare
end)

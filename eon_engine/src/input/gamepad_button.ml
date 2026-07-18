type t =
  | South | East | West | North
  | Left_bumper | Right_bumper
  | Left_trigger_btn | Right_trigger_btn
  | Start | Select | Guide
  | Left_stick_btn | Right_stick_btn
  | Dpad_up | Dpad_down | Dpad_left | Dpad_right

module Set = Set.Make (struct
  type nonrec t = t

  let compare = compare
end)

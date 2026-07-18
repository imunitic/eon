(** Engine-defined gamepad buttons — backend-agnostic.

    Named after the abstract action layout (South/East/West/North) rather than
    any vendor's labelling (A/B/X/Y, Cross/Circle/Square/Triangle). *)

type t =
  | South | East | West | North
  | Left_bumper | Right_bumper
  | Left_trigger_btn | Right_trigger_btn
  | Start | Select | Guide
  | Left_stick_btn | Right_stick_btn
  | Dpad_up | Dpad_down | Dpad_left | Dpad_right

module Set : Set.S with type elt = t

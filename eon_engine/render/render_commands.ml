type camera = {
  position : float * float;
  zoom     : float option;
  rotation : float option;
  target   : (float * float) option;
  viewport : Math.Rect.t option;
}

type texture = {
  texture_id : string;
  source     : Math.Rect.t option;
  dest       : Math.Rect.t;
  rotation   : float option;
  origin     : (float * float) option;
  tint       : Color.t option;
  layer      : int;
}

type text = {
  text     : string;
  position : float * float;
  font_id  : string;
  size     : float;
  color    : Color.t;
  layer    : int;
}

type rect_cmd = {
  rect   : Math.Rect.t;
  color  : Color.t;
  filled : bool;
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
  | `Set_camera       of camera
  | `Draw_texture     of texture
  | `Draw_text        of text
  | `Draw_rect        of rect_cmd
  | `Draw_circle      of circle
  | `Draw_line        of line
]

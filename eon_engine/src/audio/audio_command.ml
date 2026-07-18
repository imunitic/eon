type t =
  | Play_sound of {
      id          : string;
      instance_id : string option;
      volume      : float;
      pitch       : float;
      pan         : float;
      loop        : bool;
    }
  | Stop_sound       of string
  | Set_volume       of string * float
  | Set_pitch        of string * float
  | Set_pan          of string * float
  | Play_music       of { id: string; volume: float; loop: bool }
  | Stop_music
  | Set_music_volume of float
  | Crossfade_music  of { id: string; duration: float }
  | Set_master_volume of float
  | Pause_all
  | Resume_all
  | Stop_all

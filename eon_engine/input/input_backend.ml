module type S = sig
  val init     : unit -> unit
  val collect  : unit -> Raw_input_frame.t
  val shutdown : unit -> unit
end

module Null = struct
  let init ()     = ()
  let collect ()  = Raw_input_frame.empty
  let shutdown () = ()
end

module Scripted = struct
  let frames : Raw_input_frame.t list ref = ref []

  let set_frames fs = frames := fs
  let init ()       = ()

  let collect () =
    match !frames with
    | []        -> Raw_input_frame.empty
    | f :: rest -> frames := rest; f

  let shutdown () = frames := []
end

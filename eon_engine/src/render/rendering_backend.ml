module type S = sig
  type command

  val init        : unit -> unit
  val render      : command Render_stream.t -> dt:float -> Rendering_result.t
  val diagnostics : unit -> (string * string) list
  val shutdown    : unit -> unit
end

module Null : S with type command = Render_commands.command = struct
  type command = Render_commands.command

  let init ()          = ()
  let render _ ~dt:_   = Rendering_result.empty
  let diagnostics ()   = []
  let shutdown ()      = ()
end

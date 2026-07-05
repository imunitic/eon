(** Signature for rendering backends.

    A backend receives an already-populated {!Render_stream.t} and has complete
    autonomy over rendering decisions — batching, layer sorting, shader dispatch.
    The engine never calls [render] directly; it goes through {!Platform.S}. *)

module type S = sig
  type command

  val init        : unit -> unit
  val render      : command Render_stream.t -> dt:float -> Rendering_result.t
  val diagnostics : unit -> (string * string) list
  val shutdown    : unit -> unit
end

(** Null backend — discards all commands. Used by [Platform.Headless]. *)
module Null : S with type command = Render_commands.command

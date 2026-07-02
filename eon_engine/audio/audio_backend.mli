(** Audio backend seam — translates [Audio_command.t] lists to platform API calls.

    [Loop.Make] calls [init] at startup and [shutdown] on exit. After drain
    each frame the loop calls [submit] with the accumulated command list, then
    clears [Audio_command_buffer].

    The backend owns the callback thread, the ring buffer, and the mixer.
    The engine sees none of that detail — [submit] is a plain function call
    from the game thread. *)

module type S = sig
  val init     : unit -> unit
  val submit   : Audio_command.t list -> unit
  val shutdown : unit -> unit
end

(** Null backend — silent; discards all commands.
    Used by [Platform.Headless] for CI and tests. *)
module Null : S

(** Input backend seam — supplies raw input frames to the engine loop.

    The engine loop calls [collect] once per frame and writes the result
    as a [Raw_input_frame] world resource before [Buses.collect] runs.
    [init] and [shutdown] are called by [Loop.run] around the game loop. *)

module type S = sig
  val init     : unit -> unit
  val collect  : unit -> Raw_input_frame.t
  val shutdown : unit -> unit
end

(** Null backend — always returns [Raw_input_frame.empty]. *)
module Null : S

(** Scripted backend — replays a pre-set list of frames in order.
    Returns [Raw_input_frame.empty] once the list is exhausted.
    [shutdown] clears the remaining frames. Thread-unsafe; use only in tests. *)
module Scripted : sig
  include S

  (** Set the frame sequence to replay. Replaces any previously set frames. *)
  val set_frames : Raw_input_frame.t list -> unit
end

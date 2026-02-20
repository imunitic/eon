(** Default bus orchestration for {!Loop.Default}.

    Implements {!Loop.BUSES} by reading [\`Signals], [\`Events], and
    [\`Commands] services from the world and dispatching them in the
    order required by the frame invariant.
*)

(** World type this module operates on. *)
type world = World.t

(** Collect all buses at the start of a frame.

    Order: Signals → Events → Commands. *)
val collect : world -> unit

(** Drain all buses at the end of a frame.

    Order: Signals → Commands → Events. *)
val drain : world -> unit

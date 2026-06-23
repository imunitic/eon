(** Default bus orchestration for {!Loop.Default}.

    Implements {!Loop.BUSES} by dispatching the singleton bus instances from
    {!Buses.Default} in the frame order required by the core invariant.

    Frame order:
    - [collect]: Signals → Events → Commands
    - [drain]:   Signals → Commands → Events *)

val collect : unit -> unit
val drain   : unit -> unit

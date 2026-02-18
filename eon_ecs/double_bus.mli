(** Double-buffered message bus.

    Messages emitted during frame [N] are delivered when the bus is collected or
    drained in frame [N+1].
*)
include Bus.BUS

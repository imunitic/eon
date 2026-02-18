(** Single-buffered message bus.

    Emitted messages are queued and delivered when [collect] or [drain] runs in
    the same frame.
*)
include Bus.BUS

(** Engine bus orchestration for [Eon_engine.Loop.Make].

    Satisfies [Eon_engine.Loop.BUSES with type world = World.rw World.t]. Reads
    [Single_bus] / [Double_bus] instances from world services under the
    standard [`` `Signals ``], [`` `Events ``], [`` `Commands ``] keys.

    Frame order (matches core):
    - [collect]: Signals → Events → Commands
    - [drain]:   Signals → Commands → Events *)

type world = World.rw World.t

val collect : world -> unit
val drain   : world -> unit

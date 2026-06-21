(** Engine bus orchestration for [Eon_ecs.Loop.Make].

    Satisfies [Eon_ecs.Loop.BUSES with type world = Eon_ecs.World.t]. Reads
    [Single_bus] / [Double_bus] instances from world services under the
    standard [`` `Signals ``], [`` `Events ``], [`` `Commands ``] keys.

    Frame order (matches core):
    - [collect]: Signals → Events → Commands
    - [drain]:   Signals → Commands → Events *)

type world = Eon_ecs.World.t

val collect : world -> unit
val drain   : world -> unit

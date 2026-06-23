(** Engine bus orchestration for [Eon_engine.Loop.Make].

    Satisfies [Loop.BUSES]. Bus instances are closed over from [Buses.Default]
    at module init time — no world argument, no per-frame service lookups.

    Frame order (matches core):
    - [collect]: Signals → Events → Commands
    - [drain]:   Signals → Commands → Events *)

val collect : unit -> unit
val drain   : unit -> unit

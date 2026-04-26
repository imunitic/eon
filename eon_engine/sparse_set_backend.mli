(** Default sparse set backend for query execution.

    This is the default backend that wraps Eon_ecs.Query directly.
    It provides zero new logic - just a thin wrapper around the existing
    sparse set iteration functions, with additional filtering for [having] and [excludes].
*)

type world = Eon_ecs.World.t

include Query_backend.S with type world := world

(** Time-step progression manager for engine pipelines.

    Re-exports [Eon_ecs.Progress] with [Pipeline.world] threading through
    [Make_with_kind] and [Make]. Use [Make(Pipeline.Default)] for the default
    stack — the resulting [world] type will be [Eon_engine.World.t].

    [Make_with_time] extends [Make] with a pre-tick [Time] resource write.
    [Eon_ecs.Progress] is untouched by either variant.

    Example without Time:
    {[
      module Progress = Eon_engine.Progress.Make(Eon_engine.Pipeline.Default)
      let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
    ]}

    Example with Time:
    {[
      module Progress =
        Eon_engine.Progress.Make_with_time(Eon_engine.Pipeline.Default)(Time)
      let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
    ]}
*)
include module type of Eon_ecs.Progress

[@@@warning "-67"]
module Make_with_time
    (P : Eon_ecs.Pipeline.S
           with type kind = [ `Fixed | `Variable ]
            and type world = World.rw World.t)
    (T : Time.S)
  : module type of Eon_ecs.Progress.Make(P)
[@@@warning "+67"]

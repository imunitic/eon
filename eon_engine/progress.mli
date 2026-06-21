(** Time-step progression manager for engine pipelines.

    Re-exports [Eon_ecs.Progress] with [Pipeline.world] threading through
    [Make_with_kind] and [Make]. Use [Make(Pipeline.Default)] for the default
    stack — the resulting [world] type will be [Eon_engine.World.t].

    Example:
    {[
      module Progress = Eon_engine.Progress.Make(Eon_engine.Pipeline.Default)
      let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
    ]}
*)
include module type of Eon_ecs.Progress

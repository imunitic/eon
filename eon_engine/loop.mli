(** Game loop builder for the engine layer.

    Frame order per tick:
    1. [Platform.Input_backend.collect ()] — poll backend; result written as
       [Raw_input_frame] world resource before any system runs
    2. [Buses.collect]
    3. [Progress.tick] — run the pipeline
    4. [Buses.drain]
    5. [Platform.Audio_backend.submit] — submit accumulated audio commands;
       [Audio_command_buffer] is cleared immediately after

    [Loop.run] takes [~assets:(module Asset_lookup.S)] and passes it to
    [Platform.Audio_backend.init] before the loop starts. [shutdown]
    counterparts for both backends are called after the loop returns.

    Typical usage:
    {[
      module Engine_progress = Eon_engine.Progress.Make(Eon_engine.Pipeline.Default)
      module Engine_loop =
        Eon_engine.Loop.Make
          (Eon_ecs.Clock.Mtime)
          (Engine_progress)
          (Platform.Headless)
          (Eon_engine.Loop_buses)
    ]}
*)

module Make
    (_ : Eon_ecs.Loop.CLOCK)
    (Progress : sig
       type 'phase t
       type world = World.rw World.t
       val tick : 'phase t -> world:world -> dt:float -> world
     end)
    (_ : Platform.S)
    (_ : Eon_ecs.Loop.BUSES)
: sig
  val step :
    progress:'phase Progress.t ->
    world:Progress.world ->
    last_time:float ->
    now:float ->
    should_continue:(Progress.world -> bool) ->
    Progress.world * float * bool

  val run :
    progress:'phase Progress.t ->
    world:Progress.world ->
    assets:(module Asset_lookup.S) ->
    should_continue:(Progress.world -> bool) ->
    unit ->
    Progress.world
end

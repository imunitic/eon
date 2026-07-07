(** Game loop builder for the engine layer.

    Frame order per tick:
    1. [Platform.Input_backend.collect ()] — poll backend; result written as
       [Raw_input_frame] world resource before any system runs
    2. [Buses.collect]
    3. [Progress.tick] — run the pipeline (including [Render_system] if registered)
    4. [Buses.drain]
    5. [Platform.Audio_backend.submit] — submit accumulated audio commands;
       [Audio_command_buffer] is cleared immediately after
    6. [Platform.Rendering_backend.render] — consume the [Render_stream] stored
       in the world data plane by [Render_system]; no-op if no stream was stored

    [Loop.run] calls [init] on all three backends before the loop starts and
    their [shutdown] counterparts after it returns. Asset lookup is baked into each backend at
    construction time — [Loop.run] has no knowledge of assets.

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
    ?paused:(Progress.world -> bool) ->
    should_continue:(Progress.world -> bool) ->
    unit ->
    Progress.world
  (** Drive the game loop until [should_continue] returns [false].
      [~paused] defaults to [fun _ -> false]. When it returns [true],
      [dt = 0.0] is passed to [Progress.tick] — time stops, everything
      else keeps running. [last_time] still advances so there is no time
      jump on unpause. *)
end

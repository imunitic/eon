(** Game loop builder for the engine layer.

    Delegates to [Eon_ecs.Loop.Make]; typed for [World.t] when composed with
    [Eon_engine.Progress] and [Eon_engine.Loop_buses].

    Frame order:
    1. [Buses.collect]
    2. [Progress.tick]
    3. [Buses.drain]
    4. [Renderer.render]

    Typical usage:
    {[
      module Engine_progress = Eon_engine.Progress.Make(Eon_engine.Pipeline.Default)
      module Engine_loop =
        Eon_engine.Loop.Make(Eon_ecs.Clock.Mtime)(Engine_progress)(Renderer)(Eon_engine.Loop_buses)
    ]}
*)

module type CLOCK = sig
  val now : unit -> float
end

module type RENDERER = sig
  type world
  type result
  val render : world -> dt:float -> result
end

module type BUSES = sig
  val collect : unit -> unit
  val drain   : unit -> unit
end

module Make
    (_ : CLOCK)
    (Progress : sig
       type 'phase t
       type world
       val tick : 'phase t -> world:world -> dt:float -> world
     end)
    (Renderer : RENDERER with type world = Progress.world)
    (_ : BUSES)
: sig
  val step :
    progress:'phase Progress.t ->
    world:Progress.world ->
    last_time:float ->
    now:float ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    Progress.world * float * Renderer.result * bool

  val run :
    ?render_initial:bool ->
    progress:'phase Progress.t ->
    world:Progress.world ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    unit ->
    Progress.world
end

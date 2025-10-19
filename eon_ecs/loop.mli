module type CLOCK = sig
  val now : unit -> float
end

module type RENDERER = sig
  type world
  type result
  val render : world -> dt:float -> result
end

module type BUSES = sig
  type world
  val collect : world -> unit
  val drain   : world -> unit
end

module Make
    (Clock    : CLOCK)
    (Progress : sig
       type 'phase t
       type world
       val tick : 'phase t -> world:world -> dt:float -> world
     end)
    (Renderer : RENDERER with type world = Progress.world)
    (Buses    : BUSES with type world = Progress.world)
: sig
  val step :
    progress:'phase Progress.t ->
    world:Progress.world ->
    last_time:float ->
    now:float ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    Progress.world * float * Renderer.result * bool

  val run :
    progress:'phase Progress.t ->
    world:Progress.world ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    Progress.world
end

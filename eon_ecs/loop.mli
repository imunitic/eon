module type CLOCK = sig
  (** Wall-clock provider used to drive frame timing. *)
  (** Return the current time in seconds. *)
  val now : unit -> float
end

module type RENDERER = sig
  (** Rendering backend invoked after each simulation step. *)
  (** World instance rendered by the backend. *)
  type world
  (** Resulting value returned by the renderer after each frame. *)
  type result
  (** Inspect or present the world after the frame has been processed. *)
  val render : world -> dt:float -> result
end

module type BUSES = sig
  (** Message bus orchestration used to collect/drain transient data. *)
  (** World instance associated with the buses. *)
  type world
  (** Pull messages emitted in the previous frame into handler queues. *)
  val collect : world -> unit
  (** Flush message buses once systems have run, applying queued effects. *)
  val drain   : world -> unit
end

(** Generic loop builder combining a clock, progress mode, renderer, and buses. *)
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
  (** Execute a single iteration of the loop.
      @param progress progress controller to advance
      @param world world to simulate
      @param last_time timestamp of the previous frame
      @param now current timestamp
      @param should_continue predicate deciding whether to keep running
      @return updated world, the timestamp used for the next frame, the renderer
              result, and a boolean flag indicating whether to keep looping. *)
  val step :
    progress:'phase Progress.t ->
    world:Progress.world ->
    last_time:float ->
    now:float ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    Progress.world * float * Renderer.result * bool

  (** Repeatedly call {!step} until the continuation predicate returns [false].
      @param progress progress controller to advance
      @param world initial ECS world
      @param should_continue loop guard tested after each frame
      @return final world after the loop terminates. *)
  val run :
    progress:'phase Progress.t ->
    world:Progress.world ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    Progress.world
end

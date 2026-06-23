(** Wall-clock provider used to drive frame timing. *)
module type CLOCK = sig
  val now : unit -> float
end

(** Rendering backend invoked after each simulation step. *)
module type RENDERER = sig
  type world
  type result
  val render : world -> dt:float -> result
end

(** Message bus orchestration used to collect/drain transient data.

    Bus instances are closed over at module definition time; [collect] and
    [drain] take no world argument. *)
module type BUSES = sig
  val collect : unit -> unit
  val drain   : unit -> unit
end

(** Generic loop builder combining a clock, progress mode, renderer, and buses.

    Frame order:
    1. [collect]
    2. [Progress.tick]
    3. [drain]
    4. [Renderer.render]
*)
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
  (** Execute a single iteration of the loop.
      @param progress progress controller to advance
      @param world world to simulate
      @param last_time timestamp of the previous frame
      @param now current timestamp
      @param should_continue predicate deciding whether to keep running
      @return updated world, current timestamp, renderer result, and continue flag. *)
  val step :
    progress:'phase Progress.t ->
    world:Progress.world ->
    last_time:float ->
    now:float ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    Progress.world * float * Renderer.result * bool

  (** Repeatedly call {!step} until [should_continue] returns [false].

      If [render_initial] is [true], render one frame with [dt = 0.0] before
      the first simulation step. This avoids ad-hoc pre-loop rendering in apps
      that want an immediate first frame.

      Example:
      {[
        let final_world =
          Loop.run
            ~render_initial:true
            ~progress
            ~world
            ~should_continue:(fun _world _result -> true)
            ()
      ]}
  *)
  val run :
    ?render_initial:bool ->
    progress:'phase Progress.t ->
    world:Progress.world ->
    should_continue:(Progress.world -> Renderer.result -> bool) ->
    unit ->
    Progress.world
end

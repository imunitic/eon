(** Wall-clock provider used to drive frame timing. *)
module type CLOCK = sig
  val now : unit -> float
end

(** Message bus orchestration used to collect/drain transient data.

    Bus instances are closed over at module definition time; [collect] and
    [drain] take no world argument. *)
module type BUSES = sig
  val collect : unit -> unit
  val drain   : unit -> unit
end

(** Generic loop builder combining a clock, progress mode, and buses.

    Frame order:
    1. [collect]
    2. [Progress.tick]
    3. [drain]
*)
module Make
    (_ : CLOCK)
    (Progress : sig
       type 'phase t
       type world
       val tick : 'phase t -> world:world -> dt:float -> world
     end)
    (_ : BUSES)
: sig
  (** Execute a single iteration of the loop.
      @param progress progress controller to advance
      @param world world to simulate
      @param last_time timestamp of the previous frame
      @param now current timestamp
      @param should_continue predicate deciding whether to keep running
      @return updated world, current timestamp, and continue flag. *)
  val step :
    progress:'phase Progress.t ->
    world:Progress.world ->
    last_time:float ->
    now:float ->
    should_continue:(Progress.world -> bool) ->
    Progress.world * float * bool

  (** Repeatedly call {!step} until [should_continue] returns [false].

      Example:
      {[
        let final_world =
          Loop.run
            ~progress
            ~world
            ~should_continue:(fun _world -> true)
            ()
      ]}
  *)
  val run :
    progress:'phase Progress.t ->
    world:Progress.world ->
    should_continue:(Progress.world -> bool) ->
    unit ->
    Progress.world
end

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
= struct
  type world = Progress.world
  type renderer_result = Renderer.result

  let step ~progress ~world ~last_time ~now ~should_continue =
    Buses.collect world;
    let dt = now -. last_time in
    let world = Progress.tick progress ~world ~dt in
    Buses.drain world;
    let result = Renderer.render world ~dt in
    let continue = should_continue world result in
    (world, now, result, continue)

  let rec run ~progress ~world ~should_continue =
    let rec loop world last_time =
      let now = Clock.now () in
      let world, _, _, continue =
        step ~progress ~world ~last_time ~now
          ~should_continue
      in
      if continue then loop world now else world
    in
    let start = Clock.now () in
    loop world start
end

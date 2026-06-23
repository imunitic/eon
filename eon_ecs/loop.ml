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
    (Clock    : CLOCK)
    (Progress : sig
       type 'phase t
       type world
       val tick : 'phase t -> world:world -> dt:float -> world
     end)
    (Renderer : RENDERER with type world = Progress.world)
    (Buses    : BUSES)
= struct
  let step ~progress ~world ~last_time ~now ~should_continue =
    Buses.collect ();
    let dt = now -. last_time in
    let world = Progress.tick progress ~world ~dt in
    Buses.drain ();
    let result = Renderer.render world ~dt in
    let continue = should_continue world result in
    (world, now, result, continue)

  let run ?(render_initial = false) ~progress ~world ~should_continue () =
    let rec loop world last_time =
      let now = Clock.now () in
      let world, _, _, continue =
        step ~progress ~world ~last_time ~now
          ~should_continue
      in
      if continue then loop world now else world
    in
    let start = Clock.now () in
    if render_initial then
      let result = Renderer.render world ~dt:0.0 in
      if should_continue world result then loop world start else world
    else
      loop world start
end

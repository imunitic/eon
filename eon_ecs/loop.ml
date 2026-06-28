module type CLOCK = sig
  val now : unit -> float
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
    (Buses    : BUSES)
= struct
  let step ~progress ~world ~last_time ~now ~should_continue =
    Buses.collect ();
    let dt = now -. last_time in
    let world = Progress.tick progress ~world ~dt in
    Buses.drain ();
    let continue = should_continue world in
    (world, now, continue)

  let run ~progress ~world ~should_continue () =
    let rec loop world last_time =
      let now = Clock.now () in
      let world, _, continue =
        step ~progress ~world ~last_time ~now ~should_continue
      in
      if continue then loop world now else world
    in
    loop world (Clock.now ())
end

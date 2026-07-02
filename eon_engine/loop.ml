module Make
    (Clock    : Eon_ecs.Loop.CLOCK)
    (Progress : sig
       type 'phase t
       type world = World.rw World.t
       val tick : 'phase t -> world:world -> dt:float -> world
     end)
    (Platform : Platform.S)
    (Buses    : Eon_ecs.Loop.BUSES)
= struct
  let step ~progress ~world ~last_time ~now ~should_continue =
    let raw = Platform.Input_backend.collect () in
    Raw_input_frame.set world raw;
    Buses.collect ();
    let dt = now -. last_time in
    let world = Progress.tick progress ~world ~dt in
    Buses.drain ();
    (match Audio_command_buffer.get world with
     | Some buf ->
       Platform.Audio_backend.submit (Audio_command_buffer.to_list buf);
       Audio_command_buffer.clear buf
     | None -> ());
    let continue = should_continue world in
    (world, now, continue)

  let run ~progress ~world ~should_continue () =
    Platform.Input_backend.init ();
    Platform.Audio_backend.init ();
    let rec loop world last_time =
      let now = Clock.now () in
      let world, _, continue =
        step ~progress ~world ~last_time ~now ~should_continue
      in
      if continue then loop world now else world
    in
    let result = loop world (Clock.now ()) in
    Platform.Audio_backend.shutdown ();
    Platform.Input_backend.shutdown ();
    result
end

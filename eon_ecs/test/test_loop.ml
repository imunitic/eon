open Alcotest

module Loop = Eon_ecs__Loop

let event_log : string list ref = ref []
let log s = event_log := s :: !event_log

type world_state = unit
let world () : world_state = ()

module Clock_stub = struct
  let times = ref []

  let reset seq = times := seq

  let now () =
    match !times with
    | t :: rest ->
       times := rest;
       t
    | [] -> failwith "Clock_stub exhausted"
end

module Test_progress = struct
  type 'phase t = unit
  type world = world_state

  let tick () ~world ~dt =
    log (Printf.sprintf "tick %.3f" dt);
    world
end

module Test_buses = struct
  let collect () = log "collect"
  let drain   () = log "drain"
end

module Test_loop = Loop.Make(Clock_stub)(Test_progress)(Test_buses)

let test_step () =
  event_log := [];
  let w = world () in
  let should_continue _world =
    log (Printf.sprintf "continue %b" false);
    false
  in
  let last_time = 1.0 in
  let now = 1.5 in
  let _, _, continue =
    Test_loop.step
      ~progress:()
      ~world:w
      ~last_time
      ~now
      ~should_continue
  in
  let expected =
    [ "collect"
    ; "tick 0.500"
    ; "drain"
    ; "continue false"
    ]
  in
  check (list string) "step order"
    expected
    (List.rev !event_log);
  check bool "continue flag" false continue

let test_run () =
  event_log := [];
  let w = world () in
  Clock_stub.reset [ 0.0; 0.5; 1.0 ];
  let remaining = ref 2 in
  let should_continue _world =
    log (Printf.sprintf "continue %d" !remaining);
    let decision =
      if !remaining > 1 then true else false
    in
    decr remaining;
    decision
  in
  ignore
    (Test_loop.run
       ~progress:()
       ~world:w
       ~should_continue
       ());
  let expected =
    [ "collect"
    ; "tick 0.500"
    ; "drain"
    ; "continue 2"
    ; "collect"
    ; "tick 0.500"
    ; "drain"
    ; "continue 1"
    ]
  in
  check (list string) "run order"
    expected
    (List.rev !event_log);
  check int "clock exhausted" 0 (List.length !(Clock_stub.times))

let tests =
  [
    test_case "step order" `Quick test_step;
    test_case "run order" `Quick test_run;
  ]

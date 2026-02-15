open Bechamel
open Staged

module Loop = Eon_ecs__Loop
module World = Eon_ecs__World
module Signals_bus = Eon_ecs__Single_bus
module Events_bus = Eon_ecs__Double_bus
module Commands_bus = Eon_ecs__Single_bus
module Default_buses = Eon_ecs__Loop_default_buses

let fixed_should_continue _ _ = false

type mini_world = {
  mutable ticks : int;
}

module Mini_progress = struct
  type 'phase t = unit
  type world = mini_world

  let tick () ~world ~dt:_ =
    world.ticks <- world.ticks + 1;
    world
end

module Mini_renderer = struct
  type world = mini_world
  type result = unit

  let render _ ~dt:_ = ()
end

module Mini_buses = struct
  type world = mini_world

  let collect _ = ()
  let drain _ = ()
end

module Mini_loop = Loop.Make (struct let now () = 0.0 end) (Mini_progress)
    (Mini_renderer) (Mini_buses)

module Empty_progress = struct
  type 'phase t = unit
  type world = World.t

  let tick () ~world ~dt:_ = world
end

module Empty_renderer = struct
  type world = World.t
  type result = unit

  let render _ ~dt:_ = ()
end

module Empty_loop =
  Loop.Make (struct let now () = 0.0 end) (Empty_progress) (Empty_renderer)
    (Default_buses)

module Traffic_progress = struct
  type 'phase t = {
    signals_per_step : int;
    commands_per_step : int;
    events_per_step : int;
  }

  type world = World.t

  let require world key =
    match World.get_service world key with
    | Some bus -> bus
    | None -> failwith "Missing bus service for traffic benchmark"

  let tick cfg ~world ~dt:_ =
    let signals : int Signals_bus.t = require world `Signals in
    let commands : int Commands_bus.t = require world `Commands in
    let events : int Events_bus.t = require world `Events in
    for i = 1 to cfg.signals_per_step do
      Signals_bus.emit signals i
    done;
    for i = 1 to cfg.commands_per_step do
      Commands_bus.emit commands i
    done;
    for i = 1 to cfg.events_per_step do
      Events_bus.emit events i
    done;
    world
end

module Traffic_renderer = struct
  type world = World.t
  type result = unit

  let render _ ~dt:_ = ()
end

module Traffic_loop =
  Loop.Make (struct let now () = 0.0 end) (Traffic_progress) (Traffic_renderer)
    (Default_buses)

let make_world_with_default_buses () =
  let world = World.create () in
  World.add_service world `Signals (Signals_bus.create ());
  World.add_service world `Commands (Commands_bus.create ());
  World.add_service world `Events (Events_bus.create ());
  world

let mk_loop_step_minimal ~cycles =
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name = Printf.sprintf "loop-step-minimal-cyc%d" cycles in
  Test.make ~name
    (stage (fun () ->
         let world = { ticks = 0 } in
         let progress = () in
         let last_time = 0.0 in
         let now = 0.016 in
         fun () ->
           for _ = 1 to cycles do
             ignore
               (Mini_loop.step ~progress ~world ~last_time ~now
                  ~should_continue:fixed_should_continue)
           done))

let mk_loop_step_default_buses_empty ~cycles =
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name = Printf.sprintf "loop-step-default-buses-empty-cyc%d" cycles in
  Test.make ~name
    (stage (fun () ->
         let world = make_world_with_default_buses () in
         let progress = () in
         let last_time = 0.0 in
         let now = 0.016 in
         fun () ->
           for _ = 1 to cycles do
             ignore
               (Empty_loop.step ~progress ~world ~last_time ~now
                  ~should_continue:fixed_should_continue)
           done))

let mk_loop_step_default_buses_traffic ~messages ~cycles =
  if messages <= 0 then invalid_arg "messages must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "loop-step-default-buses-traffic-msg%d-cyc%d" messages cycles
  in
  Test.make ~name
    (stage (fun () ->
         let world = make_world_with_default_buses () in
         let progress =
           {
             Traffic_progress.signals_per_step = messages;
             commands_per_step = messages;
             events_per_step = messages;
           }
         in
         let last_time = 0.0 in
         let now = 0.016 in
         fun () ->
           for _ = 1 to cycles do
             ignore
               (Traffic_loop.step ~progress ~world ~last_time ~now
                  ~should_continue:fixed_should_continue)
           done))

let loop_suite =
  Test.make_grouped ~name:"loop_step"
    [
      mk_loop_step_minimal ~cycles:10_000;
      mk_loop_step_default_buses_empty ~cycles:10_000;
      mk_loop_step_default_buses_traffic ~messages:100 ~cycles:1_000;
      mk_loop_step_default_buses_traffic ~messages:1_000 ~cycles:300;
    ]

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  Benchmark_helpers.bench_with_gc cfg loop_suite;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."

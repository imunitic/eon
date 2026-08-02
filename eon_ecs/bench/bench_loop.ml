open Bechamel
open Staged

module Loop = Eon_ecs__Loop
module World = Eon_ecs__World
module Query = Eon_ecs__Query
module Entity_id = Eon_ecs__Entity_id
module Signals_bus  = Eon_ecs__Single_bus
module Events_bus   = Eon_ecs__Double_bus
module Commands_bus = Eon_ecs__Single_bus
module Default_buses = Eon_ecs__Loop_default_buses
module Buses = Eon_ecs__Buses

let fixed_should_continue _ = false

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

module Mini_buses = struct
  let collect () = ()
  let drain   () = ()
end

module Mini_loop = Loop.Make (struct let now () = 0.0 end) (Mini_progress) (Mini_buses)

module Empty_progress = struct
  type 'phase t = unit
  type world = World.t

  let tick () ~world ~dt:_ = world
end

module Empty_loop =
  Loop.Make (struct let now () = 0.0 end) (Empty_progress) (Default_buses)

module Traffic_progress = struct
  type 'phase t = {
    signals_per_step  : int;
    commands_per_step : int;
    events_per_step   : int;
  }

  type world = World.t

  let tick cfg ~world ~dt:_ =
    for i = 1 to cfg.signals_per_step do
      Signals_bus.emit (Buses.Default.signals ()) i
    done;
    for i = 1 to cfg.commands_per_step do
      Commands_bus.emit (Buses.Default.commands ()) i
    done;
    for i = 1 to cfg.events_per_step do
      Events_bus.emit (Buses.Default.events ()) i
    done;
    world
end

module Traffic_loop =
  Loop.Make (struct let now () = 0.0 end) (Traffic_progress) (Default_buses)

(* Every builder uses [Test.make_with_resource] rather than a plain [stage]d
   closure over a hoisted world. Bechamel's Staged.stage/unstage are a no-op
   identity (no built-in "setup once, time repeatedly" split -- the whole
   [unit -> 'a] passed to a plain [Test.make] reruns, in full, on every timed
   call, and a value merely RETURNED from that function -- e.g. a nested
   closure -- is never itself invoked), so a naive hoist-and-close-over-it
   approach would force every test's world to be constructed eagerly and
   stay reachable for the whole suite's run. [make_with_resource]'s
   allocate/free is Bechamel's actual API for "build once per test, time
   repeatedly, free before the next test starts" -- keeps memory bounded to
   one world at a time. Only the cycles loop of repeated Loop.step calls
   goes inside the staged function, so what's measured is steady-state
   per-step cost, not one-time setup. *)
let mk_loop_step_minimal ~cycles =
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name = Printf.sprintf "loop-step-minimal-cyc%d" cycles in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () -> { ticks = 0 })
    ~free:(fun _ -> ())
    (stage (fun world ->
         let progress = () in
         let last_time = 0.0 in
         let now = 0.016 in
         for _ = 1 to cycles do
           ignore
             (Mini_loop.step ~progress ~world ~last_time ~now
                ~should_continue:fixed_should_continue)
         done))

let mk_loop_step_default_buses_empty ~cycles =
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name = Printf.sprintf "loop-step-default-buses-empty-cyc%d" cycles in
  Test.make_with_resource ~name Test.uniq
    ~allocate:World.create
    ~free:(fun _ -> ())
    (stage (fun world ->
         let progress = () in
         let last_time = 0.0 in
         let now = 0.016 in
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
  Test.make_with_resource ~name Test.uniq
    ~allocate:World.create
    ~free:(fun _ -> ())
    (stage (fun world ->
         let progress =
           { Traffic_progress.signals_per_step = messages;
             commands_per_step = messages;
             events_per_step = messages }
         in
         let last_time = 0.0 in
         let now = 0.016 in
         for _ = 1 to cycles do
           ignore
             (Traffic_loop.step ~progress ~world ~last_time ~now
                ~should_continue:fixed_should_continue)
         done))

(* Mixed frame/phase workload: a composite Loop.step pass combining
   movement-style writes (Position += Velocity via iter2), health-style
   reads (iter1, no write), spawn/despawn churn (destroy+recreate a rotating
   slice of the entity pool), random access (get_component at precomputed
   shuffled indices), and structural churn (toggle a Tag component on a
   rotating slice). Isolated single-phase variants are also built from the
   same progress type with the other phases turned off, since phase
   benchmarks use separate isolated worlds and do not sum exactly to the
   composite mixed-frame number -- each measures its own phase's cost in
   isolation, not the interaction/contention effects the composite has. *)
module Mixed_progress = struct
  type phase_config = {
    movement : bool;
    health_read : bool;
    spawn_despawn : bool;
    random_access : bool;
    structural_churn : bool;
  }

  let full_frame =
    { movement = true; health_read = true; spawn_despawn = true;
      random_access = true; structural_churn = true }
  let movement_only =
    { movement = true; health_read = false; spawn_despawn = false;
      random_access = false; structural_churn = false }
  let health_read_only =
    { movement = false; health_read = true; spawn_despawn = false;
      random_access = false; structural_churn = false }
  let spawn_despawn_only =
    { movement = false; health_read = false; spawn_despawn = true;
      random_access = false; structural_churn = false }
  let random_access_only =
    { movement = false; health_read = false; spawn_despawn = false;
      random_access = true; structural_churn = false }
  let structural_churn_only =
    { movement = false; health_read = false; spawn_despawn = false;
      random_access = false; structural_churn = true }

  type 'phase t = {
    config : phase_config;
    position_name : string;
    velocity_name : string;
    health_name : string;
    tag_name : string;
    (* Slot array of currently-live entities; spawn/despawn churn replaces
       entries in place, so its length stays constant at [entity_count]. *)
    entities : Entity_id.t array;
    (* Permutation of slot indices into [entities], prepared outside timing,
       consumed [access_batch] entries at a time via [access_cursor]. *)
    random_access_order : int array;
    mutable churn_cursor : int;
    mutable access_cursor : int;
    mutable structural_cursor : int;
    churn_batch : int;
    access_batch : int;
    structural_batch : int;
  }

  type world = World.t

  let tick t ~world ~dt:_ =
    let n = Array.length t.entities in
    if t.config.movement then
      Query.iter2 world t.position_name t.velocity_name
        (fun entity (pos : int) (vel : int) ->
           World.set_component world entity ~name:t.position_name (pos + vel));
    if t.config.health_read then
      Query.iter1 world t.health_name (fun _entity (_v : int) -> ());
    if t.config.spawn_despawn then
      for _ = 1 to t.churn_batch do
        let idx = t.churn_cursor mod n in
        World.destroy_entity world t.entities.(idx);
        let fresh = World.create_entity world in
        World.add_component world fresh ~name:t.position_name 0;
        World.add_component world fresh ~name:t.velocity_name 1;
        World.add_component world fresh ~name:t.health_name 100;
        t.entities.(idx) <- fresh;
        t.churn_cursor <- t.churn_cursor + 1
      done;
    if t.config.random_access then
      for _ = 1 to t.access_batch do
        let order_idx = t.access_cursor mod n in
        let slot = t.random_access_order.(order_idx) in
        ignore
          (World.get_component world t.entities.(slot) ~name:t.health_name
           : int option);
        t.access_cursor <- t.access_cursor + 1
      done;
    if t.config.structural_churn then
      for _ = 1 to t.structural_batch do
        let idx = t.structural_cursor mod n in
        let entity = t.entities.(idx) in
        (match World.get_component world entity ~name:t.tag_name with
         | Some (_ : int) -> World.remove_component world entity ~name:t.tag_name
         | None -> World.add_component world entity ~name:t.tag_name 1);
        t.structural_cursor <- t.structural_cursor + 1
      done;
    world
end

module Mixed_loop =
  Loop.Make (struct let now () = 0.0 end) (Mixed_progress) (Default_buses)

let mk_loop_mixed_frame ~label ~config ~entity_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "loop-mixed-%s-entities%d-cyc%d" label entity_count cycles
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () ->
        let world = World.create () in
        let position_name = "Position" in
        let velocity_name = "Velocity" in
        let health_name = "Health" in
        let tag_name = "Tag" in
        ignore (World.register_component world ~name:position_name ~id:0);
        ignore (World.register_component world ~name:velocity_name ~id:1);
        ignore (World.register_component world ~name:health_name ~id:2);
        ignore (World.register_component world ~name:tag_name ~id:3);
        let entities =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        Array.iter
          (fun entity ->
             World.add_component world entity ~name:position_name 0;
             World.add_component world entity ~name:velocity_name 1;
             World.add_component world entity ~name:health_name 100)
          entities;
        let random_access_order = Array.init entity_count (fun i -> i) in
        let state = Random.State.make [| 0xf2a3e; entity_count |] in
        for i = entity_count - 1 downto 1 do
          let j = Random.State.int state (i + 1) in
          let tmp = random_access_order.(i) in
          random_access_order.(i) <- random_access_order.(j);
          random_access_order.(j) <- tmp
        done;
        let batch = max 1 (entity_count / 100) in
        let progress =
          { Mixed_progress.config; position_name; velocity_name; health_name;
            tag_name; entities; random_access_order;
            churn_cursor = 0; access_cursor = 0; structural_cursor = 0;
            churn_batch = batch; access_batch = batch;
            structural_batch = batch }
        in
        world, progress)
    ~free:(fun _ -> ())
    (stage (fun (world, progress) ->
         let last_time = 0.0 in
         let now = 0.016 in
         for _ = 1 to cycles do
           ignore
             (Mixed_loop.step ~progress ~world ~last_time ~now
                ~should_continue:fixed_should_continue)
         done))

let mixed_frame_suite =
  [ mk_loop_mixed_frame ~label:"full" ~config:Mixed_progress.full_frame
      ~entity_count:10_000 ~cycles:100
  ; mk_loop_mixed_frame ~label:"full" ~config:Mixed_progress.full_frame
      ~entity_count:100_000 ~cycles:20
  ; mk_loop_mixed_frame ~label:"movement-only"
      ~config:Mixed_progress.movement_only ~entity_count:10_000 ~cycles:100
  ; mk_loop_mixed_frame ~label:"health-read-only"
      ~config:Mixed_progress.health_read_only ~entity_count:10_000 ~cycles:100
  ; mk_loop_mixed_frame ~label:"spawn-despawn-only"
      ~config:Mixed_progress.spawn_despawn_only ~entity_count:10_000 ~cycles:100
  ; mk_loop_mixed_frame ~label:"random-access-only"
      ~config:Mixed_progress.random_access_only ~entity_count:10_000 ~cycles:100
  ; mk_loop_mixed_frame ~label:"structural-churn-only"
      ~config:Mixed_progress.structural_churn_only ~entity_count:10_000
      ~cycles:100
  ]

let loop_suite =
  Test.make_grouped ~name:"loop_step"
    (List.concat
       [ [ mk_loop_step_minimal ~cycles:10_000
         ; mk_loop_step_default_buses_empty ~cycles:10_000
         ; mk_loop_step_default_buses_traffic ~messages:100 ~cycles:1_000
         ; mk_loop_step_default_buses_traffic ~messages:1_000 ~cycles:300
         ]
       ; mixed_frame_suite
       ])

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  Benchmark_helpers.bench_with_gc cfg loop_suite;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."

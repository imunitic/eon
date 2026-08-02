open Bechamel
open Staged

module World = Eon_ecs__World

let init_world_with_position_components entity_count =
  let world = World.create () in
  ignore (World.register_component world ~name:"Position" ~id:0);
  let entities = Array.init entity_count (fun _ -> World.create_entity world) in
  Array.iteri
    (fun i entity -> World.add_component world entity ~name:"Position" i)
    entities;
  world, entities

(* Every builder uses [Test.make_with_resource] rather than a plain [stage]d
   closure over a hoisted world. Bechamel's Staged.stage/unstage are a no-op
   identity (no built-in "setup once, time repeatedly" split -- the whole
   [unit -> 'a] passed to a plain [Test.make] reruns, in full, on every timed
   call), so a naive hoist-and-close-over-it approach would force every
   test's world to be constructed eagerly and stay reachable for the whole
   suite's run, making Bechamel's per-sample [Gc.compact] pass over an
   ever-growing cumulative heap. [make_with_resource]'s allocate/free is
   Bechamel's actual API for "build once per test, time repeatedly, free
   before the next test starts" -- keeps memory bounded to one world at a
   time. These benchmarks only read (get_component) or idempotently update
   (set_component on an already-present component) a static entity set, so
   the allocate phase safely differs from the timed loop -- no structural
   mutation happens during timing. *)
let mk_world_set_component ~entity_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "world-set-component-entities%d-cyc%d" entity_count cycles
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () -> init_world_with_position_components entity_count)
    ~free:(fun _ -> ())
    (stage (fun (world, entities) ->
         for cycle = 1 to cycles do
           Array.iteri
             (fun i entity ->
               World.set_component world entity ~name:"Position" (i + cycle))
             entities
         done))

let mk_world_get_component_hit ~entity_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "world-get-component-hit-entities%d-cyc%d"
      entity_count cycles
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () -> init_world_with_position_components entity_count)
    ~free:(fun _ -> ())
    (stage (fun (world, entities) ->
         for _ = 1 to cycles do
           Array.iter
             (fun entity ->
               ignore (World.get_component world entity ~name:"Position"
                         : int option))
             entities
         done))

let mk_world_get_component_mixed ~entity_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "world-get-component-mixed-entities%d-cyc%d"
      entity_count cycles
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () ->
        let world = World.create () in
        ignore (World.register_component world ~name:"Position" ~id:0);
        let with_component =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        Array.iteri
          (fun i entity -> World.add_component world entity ~name:"Position" i)
          with_component;
        let without_component =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        let query_entities =
          Array.init entity_count (fun i ->
              if i land 1 = 0 then with_component.(i)
              else without_component.(i))
        in
        world, query_entities)
    ~free:(fun _ -> ())
    (stage (fun (world, query_entities) ->
         for _ = 1 to cycles do
           Array.iter
             (fun entity ->
               ignore (World.get_component world entity ~name:"Position"
                         : int option))
             query_entities
         done))

let mk_world_get_component_random50 ~entity_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "world-get-component-random50-entities%d-cyc%d"
      entity_count cycles
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () ->
        let world = World.create () in
        ignore (World.register_component world ~name:"Position" ~id:0);
        let with_component =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        Array.iteri
          (fun i entity -> World.add_component world entity ~name:"Position" i)
          with_component;
        let without_component =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        let state = Random.State.make [| 0xA11CE; entity_count |] in
        let query_entities =
          Array.init entity_count (fun i ->
              if Random.State.bool state then with_component.(i)
              else without_component.(i))
        in
        world, query_entities)
    ~free:(fun _ -> ())
    (stage (fun (world, query_entities) ->
         for _ = 1 to cycles do
           Array.iter
             (fun entity ->
               ignore (World.get_component world entity ~name:"Position"
                         : int option))
             query_entities
         done))

let mk_world_get_component_clustered ~entity_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "world-get-component-clustered-entities%d-cyc%d"
      entity_count cycles
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () ->
        let world = World.create () in
        ignore (World.register_component world ~name:"Position" ~id:0);
        let with_component =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        Array.iteri
          (fun i entity -> World.add_component world entity ~name:"Position" i)
          with_component;
        let without_component =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        let query_entities =
          Array.init entity_count (fun i ->
              if i < entity_count / 2 then with_component.(i)
              else without_component.(i))
        in
        world, query_entities)
    ~free:(fun _ -> ())
    (stage (fun (world, query_entities) ->
         for _ = 1 to cycles do
           Array.iter
             (fun entity ->
               ignore (World.get_component world entity ~name:"Position"
                         : int option))
             query_entities
         done))

let world_component_suite =
  Test.make_grouped ~name:"world_component"
    [ mk_world_set_component ~entity_count:1_000 ~cycles:10
    ; mk_world_set_component ~entity_count:10_000 ~cycles:5
    ; mk_world_get_component_hit ~entity_count:1_000 ~cycles:10
    ; mk_world_get_component_hit ~entity_count:10_000 ~cycles:5
    ; mk_world_get_component_hit ~entity_count:100_000 ~cycles:2
    ; mk_world_get_component_hit ~entity_count:1_000_000 ~cycles:1
    ; mk_world_get_component_mixed ~entity_count:1_000 ~cycles:10
    ; mk_world_get_component_mixed ~entity_count:10_000 ~cycles:5
    ; mk_world_get_component_mixed ~entity_count:100_000 ~cycles:2
    ; mk_world_get_component_mixed ~entity_count:1_000_000 ~cycles:1
    ; mk_world_get_component_random50 ~entity_count:1_000 ~cycles:10
    ; mk_world_get_component_random50 ~entity_count:10_000 ~cycles:5
    ; mk_world_get_component_random50 ~entity_count:100_000 ~cycles:2
    ; mk_world_get_component_random50 ~entity_count:1_000_000 ~cycles:1
    ; mk_world_get_component_clustered ~entity_count:1_000 ~cycles:10
    ; mk_world_get_component_clustered ~entity_count:10_000 ~cycles:5
    ; mk_world_get_component_clustered ~entity_count:100_000 ~cycles:2
    ; mk_world_get_component_clustered ~entity_count:1_000_000 ~cycles:1
    ]

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  Benchmark_helpers.bench_with_gc cfg world_component_suite;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."

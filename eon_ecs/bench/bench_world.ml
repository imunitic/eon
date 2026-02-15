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

let mk_world_set_component ~entity_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if cycles <= 0 then invalid_arg "cycles must be > 0";
  let name =
    Printf.sprintf "world-set-component-entities%d-cyc%d" entity_count cycles
  in
  Test.make ~name
    (stage (fun () ->
         let world, entities = init_world_with_position_components entity_count in
         fun () ->
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
  Test.make ~name
    (stage (fun () ->
         let world, entities = init_world_with_position_components entity_count in
         fun () ->
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
  Test.make ~name
    (stage (fun () ->
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
         fun () ->
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
  Test.make ~name
    (stage (fun () ->
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
         fun () ->
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
  Test.make ~name
    (stage (fun () ->
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
         fun () ->
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
    ; mk_world_get_component_mixed ~entity_count:1_000 ~cycles:10
    ; mk_world_get_component_mixed ~entity_count:10_000 ~cycles:5
    ; mk_world_get_component_random50 ~entity_count:1_000 ~cycles:10
    ; mk_world_get_component_random50 ~entity_count:10_000 ~cycles:5
    ; mk_world_get_component_clustered ~entity_count:1_000 ~cycles:10
    ; mk_world_get_component_clustered ~entity_count:10_000 ~cycles:5
    ]

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  Benchmark_helpers.bench_with_gc cfg world_component_suite;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."

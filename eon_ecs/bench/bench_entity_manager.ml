open Bechamel
open Bechamel.Toolkit
open Staged

module Entity_manager = Eon_ecs__Entity_manager
module Entity_id = Eon_ecs__Entity_id
module World = Eon_ecs__World

let mk_entity_manager_add_remove count =
  Test.make ~name:(Printf.sprintf "add/remove-%d" count)
    (stage (fun () ->
         let em = Entity_manager.create count in
         for _ = 1 to count do
           let entity = Entity_manager.create_entity em in
           Entity_manager.destroy_entity em entity
         done))

let mk_entity_manager_batch_cycles ~capacity ~batch_size ~cycles =
  let name =
    Printf.sprintf "batch-create/destroy-cap%d-batch%d-cyc%d"
      capacity batch_size cycles
  in
  Test.make ~name
    (stage (fun () ->
         let em = Entity_manager.create capacity in
         let scratch = Array.make batch_size Entity_id.invalid in
         for cycle = 1 to cycles do
           for i = 0 to batch_size - 1 do
             scratch.(i) <- Entity_manager.create_entity em
           done;
           if cycle land 1 = 0 then
             for i = 0 to batch_size - 1 do
               Entity_manager.destroy_entity em scratch.(i)
             done
           else
             for i = batch_size - 1 downto 0 do
               Entity_manager.destroy_entity em scratch.(i)
             done
         done))

let mk_entity_manager_reuse ~capacity ~batch_size ~cycles =
  let name =
    Printf.sprintf "reuse-cycle-cap%d-batch%d-cyc%d" capacity batch_size cycles
  in
  Test.make ~name
    (stage (fun () ->
         let mgr = Entity_manager.create capacity in
         let scratch = Array.make batch_size Entity_id.invalid in
         for _ = 1 to cycles do
           for i = 0 to batch_size - 1 do
             scratch.(i) <- Entity_manager.create_entity mgr
           done;
           for i = 0 to batch_size - 1 do
             Entity_manager.destroy_entity mgr scratch.(i)
           done
         done))

let mk_entity_manager_destroy_random_subsets ~capacity ~destroy_fraction ~cycles =
  if destroy_fraction <= 0.0 || destroy_fraction > 1.0 then
    invalid_arg "destroy_fraction must be in (0, 1]";
  let destroy_count =
    int_of_float (floor (float capacity *. destroy_fraction))
    |> max 1 |> min capacity
  in
  let name =
    Printf.sprintf "destroy-random-subset-cap%d-frac%d-cyc%d" capacity
      (int_of_float (destroy_fraction *. 100.0))
      cycles
  in
  Test.make ~name
    (stage (fun () ->
         let mgr = Entity_manager.create capacity in
         let pool =
           Array.init capacity (fun _ -> Entity_manager.create_entity mgr)
         in
         let state = Random.State.make [| 0xC0FFEE; capacity; destroy_count |] in
         for _ = 1 to cycles do
           (* Partial Fisher-Yates shuffle to pick the subset without allocations. *)
           for i = 0 to destroy_count - 1 do
             let swap_idx = i + Random.State.int state (capacity - i) in
             let tmp = pool.(i) in
             pool.(i) <- pool.(swap_idx);
             pool.(swap_idx) <- tmp
           done;
           for i = 0 to destroy_count - 1 do
             Entity_manager.destroy_entity mgr pool.(i)
           done;
           for i = 0 to destroy_count - 1 do
             pool.(i) <- Entity_manager.create_entity mgr
           done
         done))

let mk_entity_manager_tapered_churn ~capacity ~occupancy ~max_delta ~cycles =
  if occupancy <= 0.0 || occupancy > 1.0 then
    invalid_arg "occupancy must be in (0, 1]";
  if max_delta <= 0 then invalid_arg "max_delta must be > 0";
  let initial_count =
    int_of_float (floor (float capacity *. occupancy)) |> max 1 |> min capacity
  in
  let name =
    Printf.sprintf "tapered-churn-cap%d-occ%d-delta%d-cyc%d" capacity
      (int_of_float (occupancy *. 100.0))
      max_delta cycles
  in
  Test.make ~name
    (stage (fun () ->
         let mgr = Entity_manager.create capacity in
         let pool = Array.make capacity Entity_id.invalid in
         for i = 0 to initial_count - 1 do
           pool.(i) <- Entity_manager.create_entity mgr
         done;
         let alive_count = ref initial_count in
         let target = initial_count in
         let state = Random.State.make [| 0xBEEF; capacity; max_delta |] in
         for _ = 1 to cycles do
           let destroy_req = Random.State.int state (max_delta + 1) in
           let destroy_count = min !alive_count destroy_req in
           if destroy_count > 0 then (
             for _ = 1 to destroy_count do
               let idx = Random.State.int state !alive_count in
               let entity = pool.(idx) in
               Entity_manager.destroy_entity mgr entity;
               decr alive_count;
               pool.(idx) <- pool.(!alive_count);
               pool.(!alive_count) <- Entity_id.invalid
             done);
           let gap = target - !alive_count in
           let gap_fix = if gap <= 0 then 0 else min gap max_delta in
           let base_spawn = Random.State.int state (max_delta + 1) in
           let spawn_count =
             min (capacity - !alive_count) (base_spawn + gap_fix)
           in
           for _ = 1 to spawn_count do
             let entity = Entity_manager.create_entity mgr in
             pool.(!alive_count) <- entity;
             incr alive_count
           done
         done))

let mk_world_attach_detach ~entity_count ~component_count ~cycles =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if component_count <= 0 then invalid_arg "component_count must be > 0";
  let name =
    Printf.sprintf "attach-detach-world-entities%d-comps%d-cyc%d" entity_count
      component_count cycles
  in
  Test.make ~name
    (stage (fun () ->
         let world = World.create () in
         let components =
           Array.init component_count (fun idx ->
               let name = Printf.sprintf "C%d" idx in
               ignore (World.register_component world ~name ~id:idx);
               name)
         in
         let entities =
           Array.init entity_count (fun _ -> World.create_entity world)
         in
         for _ = 1 to cycles do
           for i = 0 to entity_count - 1 do
             let entity = entities.(i) in
             for j = 0 to component_count - 1 do
               let name = components.(j) in
               World.add_component world entity ~name (i + j)
             done
           done;
           for i = 0 to entity_count - 1 do
             let entity = entities.(i) in
             for j = 0 to component_count - 1 do
               World.remove_component world entity ~name:components.(j)
             done
           done
         done))

let entity_manager_suite =
  Test.make_grouped ~name:"entity_manager"
    [ mk_entity_manager_add_remove 1_000
    ; mk_entity_manager_add_remove 10_000
    ; mk_entity_manager_batch_cycles ~capacity:5_000 ~batch_size:1_000 ~cycles:5
    ; mk_entity_manager_batch_cycles ~capacity:50_000 ~batch_size:10_000 ~cycles:5
    ; mk_entity_manager_tapered_churn ~capacity:10_000 ~occupancy:0.9
        ~max_delta:512 ~cycles:20
    ; mk_entity_manager_destroy_random_subsets ~capacity:10_000 ~destroy_fraction:0.25
        ~cycles:10
    ; mk_entity_manager_reuse ~capacity:5_000 ~batch_size:1_000 ~cycles:5
    ; mk_entity_manager_reuse ~capacity:50_000 ~batch_size:10_000 ~cycles:5
    ; mk_world_attach_detach ~entity_count:5_000 ~component_count:4 ~cycles:5
    ]

let instances =
  [ Toolkit.Instance.monotonic_clock ]

let benchmark cfg =
  Benchmark.all cfg instances entity_manager_suite

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  let raw = benchmark cfg in
  let analyzed =
    Benchmark_helpers.analyze_single_instance Toolkit.Instance.monotonic_clock
      raw
  in
  Benchmark_helpers.pp_results analyzed;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."


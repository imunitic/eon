open Bechamel
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

(* Spawn / random despawn: pre-creates all entities and a full deterministic
   shuffle of the destroy order outside timing, then measures ONLY the
   destroy pass -- unlike [mk_entity_manager_destroy_random_subsets], which
   recreates a subset every cycle inside the timed closure.

   Uses [Test.make_with_resource ... Test.multiple] rather than a plain
   [stage]d closure: destroying every entity in [pool] is a one-shot
   operation (a second pass over the same pool would double-destroy already-
   freed slots), so each timed call needs its OWN freshly-allocated pool,
   not a hoisted one reused across repeated calls. [Test.multiple] is
   Bechamel's API for exactly that -- allocate a fresh resource per call
   (population/shuffle excluded from the timed portion either way), rather
   than [Test.uniq]'s one-resource-for-the-whole-test. *)
let mk_entity_manager_despawn_only ~capacity =
  if capacity <= 0 then invalid_arg "capacity must be > 0";
  let name = Printf.sprintf "despawn-only-cap%d" capacity in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () ->
        let mgr = Entity_manager.create capacity in
        let pool =
          Array.init capacity (fun _ -> Entity_manager.create_entity mgr)
        in
        let state = Random.State.make [| 0x5eed5; capacity |] in
        (* Full Fisher-Yates shuffle, prepared outside timing. *)
        for i = capacity - 1 downto 1 do
          let j = Random.State.int state (i + 1) in
          let tmp = pool.(i) in
          pool.(i) <- pool.(j);
          pool.(j) <- tmp
        done;
        mgr, pool)
    ~free:(fun _ -> ())
    (stage (fun (mgr, pool) ->
         for i = 0 to capacity - 1 do
           Entity_manager.destroy_entity mgr pool.(i)
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

(* Random add/remove component churn: two independent deterministic
   permutations of entity order (one for insertion, one for removal),
   prepared outside timing -- each work item in the timed closure is one
   add+remove cycle. Unlike [mk_world_attach_detach]'s sequential bulk
   attach-all-then-detach-all, this exercises random-order access into the
   component's sparse set on both sides.

   Uses [Test.multiple] (see [mk_entity_manager_despawn_only]'s comment) --
   adding, then removing, the component on every entity is a one-shot pass;
   a second pass against the same world would re-add an already-present
   component rather than exercise a fresh insert. *)
let mk_world_random_add_remove ~entity_count =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  let name = Printf.sprintf "random-add-remove-entities%d" entity_count in
  let shuffle state arr =
    for i = Array.length arr - 1 downto 1 do
      let j = Random.State.int state (i + 1) in
      let tmp = arr.(i) in
      arr.(i) <- arr.(j);
      arr.(j) <- tmp
    done
  in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () ->
        let world = World.create () in
        ignore (World.register_component world ~name:"Position" ~id:0);
        let entities =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        let insert_order = Array.copy entities in
        let remove_order = Array.copy entities in
        shuffle (Random.State.make [| 0x1c5eed; entity_count |]) insert_order;
        shuffle (Random.State.make [| 0x2e3ea7; entity_count |]) remove_order;
        world, insert_order, remove_order)
    ~free:(fun _ -> ())
    (stage (fun (world, insert_order, remove_order) ->
         for i = 0 to entity_count - 1 do
           World.add_component world insert_order.(i) ~name:"Position" i
         done;
         for i = 0 to entity_count - 1 do
           World.remove_component world remove_order.(i) ~name:"Position"
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

(* Bulk/single insert workload. eon_ecs has one creation path (create_entity
   + add_component per component, no batch API), so this collapses bulk vs.
   single insert into one shape -- [component_count = 1] models "single
   insert", larger counts model "bulk" with more per-entity attach work.
   Unlike [mk_world_attach_detach], this times ONLY entity creation +
   component attachment: no detach/destroy in the timed closure, so it
   isolates the pure insert cost.

   Uses [Test.multiple] (see [mk_entity_manager_despawn_only]'s comment) so
   every timed call inserts into a fresh, empty world -- reusing one
   ever-growing world across repeated calls (Test.uniq) would make later
   calls measure insertion into a progressively larger world, not a
   comparable "insert cost" each time. *)
let mk_world_bulk_insert ~entity_count ~component_count =
  if entity_count <= 0 then invalid_arg "entity_count must be > 0";
  if component_count <= 0 then invalid_arg "component_count must be > 0";
  let name =
    Printf.sprintf "bulk-insert-world-entities%d-comps%d" entity_count
      component_count
  in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () ->
        let world = World.create () in
        let components =
          Array.init component_count (fun idx ->
              let name = Printf.sprintf "C%d" idx in
              ignore (World.register_component world ~name ~id:idx);
              name)
        in
        world, components)
    ~free:(fun _ -> ())
    (stage (fun (world, components) ->
         for i = 0 to entity_count - 1 do
           let entity = World.create_entity world in
           for j = 0 to component_count - 1 do
             World.add_component world entity ~name:components.(j) (i + j)
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
    ; mk_world_bulk_insert ~entity_count:10_000 ~component_count:1
    ; mk_world_bulk_insert ~entity_count:10_000 ~component_count:4
    ; mk_world_bulk_insert ~entity_count:100_000 ~component_count:4
    ; mk_world_bulk_insert ~entity_count:1_000_000 ~component_count:4
    ; mk_entity_manager_despawn_only ~capacity:10_000
    ; mk_entity_manager_despawn_only ~capacity:100_000
    ; mk_entity_manager_despawn_only ~capacity:1_000_000
    ; mk_world_random_add_remove ~entity_count:10_000
    ; mk_world_random_add_remove ~entity_count:100_000
    ; mk_world_random_add_remove ~entity_count:1_000_000
    ]

let instances =
  [ Toolkit.Instance.monotonic_clock
  ; Toolkit.Instance.minor_allocated
  ; Toolkit.Instance.major_allocated
  ]

let benchmark cfg =
  Benchmark.all cfg instances entity_manager_suite

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  let raw = benchmark cfg in
  List.iter
    (fun instance ->
       let analyzed = Benchmark_helpers.analyze_single_instance instance raw in
       Benchmark_helpers.pp_results analyzed)
    instances;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."


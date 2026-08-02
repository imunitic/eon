(* Diagnostic benchmarks investigating (and resolving) the question in the
   second brain's "why random-add-remove and despawn-only degrade
   non-flat at 1M scale" research note: BENCHMARKS.md (ecs-047) showed
   despawn-only degrading ~1.8x (20->36 ns/entity) and random-add-remove
   ~4x (21->89 ns/op) from 100k to 1M entities, while read paths
   (get_component, prepared iteration) stay flat. Not part of the
   SkyECS-derived taxonomy suite -- these isolate *why*, by varying one
   structural factor at a time against source-grounded hypotheses (read
   sparse_set.ml, entity_manager.ml, component_registry.ml before writing
   these). Kept wired into BENCH_NAMES/bench-ci going forward as a
   standing regression check on cache-locality/growth cost, not just a
   one-off diagnostic -- if these numbers ever stop being flat where they
   should be flat, that's worth noticing.

   H1 (despawn-only) -- CONFIRMED: Entity_manager.create pre-sizes its
   generations/free_list arrays to the full target capacity up front (see
   mk_entity_manager_despawn_only in bench_entity_manager.ml) -- no array
   growth ever happens during its timed destroy pass. mk_despawn_sequential
   below stays flat (~14-20 ns/entity, 10k-1m) while the original shuffled
   despawn-only degrades to 35.6 ns/entity at 1m -- pure cache/TLB effect
   from shuffled-order access into a large array, not a structural cost.

   H2 (random-add-remove) -- ONLY A MINOR CONTRIBUTOR: World.create ()'s
   "Position" Sparse_set starts at its default capacity (128) and is never
   pre-populated before the timed portion, so ~13 doublings (each
   reallocating+blitting three backing arrays) happen *inside* the timed
   add_component loop. Pregrowing it ahead of time (mk_world_add_remove_
   pregrown) only trims 1m-entity cost from 84.15 to 77.65 ns/op (~8%) --
   the real cause turned out to be the same as H1: mk_world_add_remove_
   pregrown_sequential (pregrown AND sequential) is flat at ~21 ns/op from
   10k to 1m, while every shuffled variant (cold or pregrown) degrades to
   ~78-84 ns/op at 1m. Cache locality dominates; growth cost is real but
   secondary (~15-19% at 1m, confirmed directly via mk_sparse_set_insert_
   cold vs. _pregrown, which bypass World/Entity_manager entirely). *)

open Bechamel
open Staged

module World = Eon_ecs__World
module Entity_manager = Eon_ecs__Entity_manager
module Entity_id = Eon_ecs__Entity_id
module Sparse_set = Eon_ecs__Sparse_set

let shuffle state arr =
  for i = Array.length arr - 1 downto 1 do
    let j = Random.State.int state (i + 1) in
    let tmp = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- tmp
  done

(* Control: Entity_manager.create_entity alone, pre-sized capacity (no
   growth), naturally sequential index assignment. Expected flat if
   create_entity itself has no scale-dependent cost -- a sanity check the
   other results can be read against. *)
let mk_create_only ~capacity =
  let name = Printf.sprintf "create-only-cap%d" capacity in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () -> Entity_manager.create capacity)
    ~free:(fun _ -> ())
    (stage (fun mgr ->
         for _ = 1 to capacity do
           ignore (Entity_manager.create_entity mgr : Entity_id.t)
         done))

(* H1: despawn-only, sequential (creation) order instead of shuffled.
   Compare directly against bench_entity_manager.ml's despawn-only-cap*. *)
let mk_despawn_sequential ~capacity =
  let name = Printf.sprintf "despawn-sequential-cap%d" capacity in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () ->
        let mgr = Entity_manager.create capacity in
        let pool =
          Array.init capacity (fun _ -> Entity_manager.create_entity mgr)
        in
        mgr, pool)
    ~free:(fun _ -> ())
    (stage (fun (mgr, pool) ->
         for i = 0 to capacity - 1 do
           Entity_manager.destroy_entity mgr pool.(i)
         done))

(* H2, isolated further: Sparse_set growth cost alone, with World/
   Entity_manager/Component_registry entirely out of the picture. Insert n
   sequential integer keys either cold (default capacity 128, must grow)
   or pregrown (created at ~capacity:n, never grows during the timed
   inserts). *)
let mk_sparse_set_insert_cold ~n =
  let name = Printf.sprintf "sparse-set-insert-cold-%d" n in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () -> Sparse_set.Int.create ())
    ~free:(fun _ -> ())
    (stage (fun set ->
         for i = 0 to n - 1 do
           Sparse_set.Int.add set i i
         done))

let mk_sparse_set_insert_pregrown ~n =
  let name = Printf.sprintf "sparse-set-insert-pregrown-%d" n in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () -> Sparse_set.Int.create ~capacity:n ())
    ~free:(fun _ -> ())
    (stage (fun set ->
         for i = 0 to n - 1 do
           Sparse_set.Int.add set i i
         done))

(* H2 at the World level: same add-then-remove shape as
   bench_entity_manager.ml's mk_world_random_add_remove (cold-start
   Position sparse set), reproduced here for a side-by-side report, plus
   a pregrown variant whose allocate phase does an untimed warm-up
   add+remove pass over every entity first -- forcing the sparse set to
   its full size before the timed portion, which then does a genuine
   fresh add/remove pass against already-large (but empty) backing
   arrays. *)
let mk_world_add_remove_cold ~entity_count =
  let name = Printf.sprintf "world-add-remove-cold-entities%d" entity_count in
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

let mk_world_add_remove_pregrown ~entity_count =
  let name =
    Printf.sprintf "world-add-remove-pregrown-entities%d" entity_count
  in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () ->
        let world = World.create () in
        ignore (World.register_component world ~name:"Position" ~id:0);
        let entities =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        (* Untimed warm-up: grow the Position sparse set to its full size,
           then empty it back out, before timing starts. *)
        Array.iter
          (fun e -> World.add_component world e ~name:"Position" 0)
          entities;
        Array.iter
          (fun e -> World.remove_component world e ~name:"Position")
          entities;
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

(* Closing the loop: neither growth (H2, only ~8% at 1m) nor being
   World-level rather than raw-Sparse_set fully explains
   world-add-remove's ~4x degradation -- both the cold and pregrown
   variants above still shuffle insert/remove order. This is the missing
   control: pregrown (no growth cost) AND sequential (no shuffle), mirrocing
   despawn-sequential's role for despawn-only. If this flattens the curve,
   H1 (cache locality from shuffled access) is confirmed as the dominant
   cause for world-add-remove too, with growth as a real but minor
   secondary contributor. *)
let mk_world_add_remove_pregrown_sequential ~entity_count =
  let name =
    Printf.sprintf "world-add-remove-pregrown-sequential-entities%d"
      entity_count
  in
  Test.make_with_resource ~name Test.multiple
    ~allocate:(fun () ->
        let world = World.create () in
        ignore (World.register_component world ~name:"Position" ~id:0);
        let entities =
          Array.init entity_count (fun _ -> World.create_entity world)
        in
        Array.iter
          (fun e -> World.add_component world e ~name:"Position" 0)
          entities;
        Array.iter
          (fun e -> World.remove_component world e ~name:"Position")
          entities;
        world, entities)
    ~free:(fun _ -> ())
    (stage (fun (world, entities) ->
         Array.iteri
           (fun i e -> World.add_component world e ~name:"Position" i)
           entities;
         Array.iter
           (fun e -> World.remove_component world e ~name:"Position")
           entities))

let suite =
  Test.make_grouped ~name:"cache_locality"
    [ mk_create_only ~capacity:10_000
    ; mk_create_only ~capacity:100_000
    ; mk_create_only ~capacity:1_000_000
    ; mk_despawn_sequential ~capacity:10_000
    ; mk_despawn_sequential ~capacity:100_000
    ; mk_despawn_sequential ~capacity:1_000_000
    ; mk_sparse_set_insert_cold ~n:10_000
    ; mk_sparse_set_insert_cold ~n:100_000
    ; mk_sparse_set_insert_cold ~n:1_000_000
    ; mk_sparse_set_insert_pregrown ~n:10_000
    ; mk_sparse_set_insert_pregrown ~n:100_000
    ; mk_sparse_set_insert_pregrown ~n:1_000_000
    ; mk_world_add_remove_cold ~entity_count:10_000
    ; mk_world_add_remove_cold ~entity_count:100_000
    ; mk_world_add_remove_cold ~entity_count:1_000_000
    ; mk_world_add_remove_pregrown ~entity_count:10_000
    ; mk_world_add_remove_pregrown ~entity_count:100_000
    ; mk_world_add_remove_pregrown ~entity_count:1_000_000
    ; mk_world_add_remove_pregrown_sequential ~entity_count:10_000
    ; mk_world_add_remove_pregrown_sequential ~entity_count:100_000
    ; mk_world_add_remove_pregrown_sequential ~entity_count:1_000_000
    ]

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  Benchmark_helpers.bench_with_gc cfg suite;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."

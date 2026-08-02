open Bechamel
open Staged

module Query = Eon_ecs__Query

type distribution_case = {
  label : string;
  distribution : int -> int -> bool;
}

let distribution_cases =
  let open Benchmark_helpers in
  [ { label = "default"; distribution = default_distribution }
  ; { label = "all"; distribution = distribution_all }
  ; { label = "alternating"; distribution = distribution_alternating }
  ; { label = "every-2"; distribution = distribution_every 2 }
  ; { label = "every-5"; distribution = distribution_every 5 }
  ; { label = "gradient-p10-peak4";
      distribution = distribution_gradient ~period:10 ~peak:4 }
  ; { label = "random-p50-seed42";
      distribution = distribution_random ~seed:42 ~probability:0.5 () }
  ]

(* Models "fragmented iteration": each component present on only a small,
   scattered fraction of a large world. Every component in a signature draws
   membership independently at the same low probability, so a multi-component
   iterN's match count shrinks geometrically with arity (~entity_count *
   p^component_count) even though the smallest individual sparse set is not
   itself tiny -- the sparse-set analogue of archetype-fragmentation cost.
   Less extreme than the dedicated near-disjoint adversarial-worst-case
   workload below, which targets ecs-050's Cached_backend baseline
   specifically. *)
let fragmented_distribution_cases =
  let open Benchmark_helpers in
  [ { label = "fragmented-p5-seed7";
      distribution = distribution_random ~seed:7 ~probability:0.05 () }
  ; { label = "fragmented-p1-seed7";
      distribution = distribution_random ~seed:7 ~probability:0.01 () }
  ]

(* Sparse-set adversarial worst case: components present on only ~0.1% of a
   large world, each drawing membership independently (a single shared
   Random.State advances across every (entity, component-index) draw in
   populate_world, so different components in the signature get distinct,
   near-uncorrelated membership). At 100k-1m scale, 0.1% is still hundreds
   to low thousands of entities -- the "smallest" involved sparse set is not
   small in absolute terms, but because the sets are drawn independently
   their intersection is close to empty. The smallest-set-first scan walks
   the whole smallest set and rejects almost every candidate: no equivalent
   cost exists in an archetype/table-based ECS, where this shows up instead
   as table fragmentation. This is the baseline workload against which
   ecs-050's Cached_backend is measured. *)
let adversarial_distribution_cases =
  let open Benchmark_helpers in
  [ { label = "adversarial-p0.1-seed13";
      distribution = distribution_random ~seed:13 ~probability:0.001 () }
  ]

(* Every builder below uses [Test.make_with_resource] rather than a plain
   [stage]d closure over a hoisted world. Bechamel's Staged.stage/unstage are
   a no-op identity (the whole [unit -> 'a] passed to a plain [Test.make]
   reruns, in full, on every timed call -- there's no built-in "setup once,
   time repeatedly" split), so a naive hoist-and-close-over-it approach
   forces every (size, distribution) case's world to be constructed eagerly
   when the suite list is built and to stay reachable for the entire
   process's run (all cases are held by the top-level [suite] value passed
   to one [Benchmark.all] call). With dozens of cases at up to 1m entities,
   that makes Bechamel's per-sample [Gc.compact] pass over an
   ever-growing cumulative heap, and suite runtime blows up superlinearly.
   [Test.make_with_resource] is Bechamel's actual API for "allocate once per
   test, time repeatedly, then free before the next test starts" -- each
   world is alive only for the duration of its own test, keeping memory (and
   GC-compaction cost) bounded to one world at a time instead of the whole
   suite. *)

let mk_query_iter1 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter1-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count ~component_count
                 ~distribution
             in
             match components with
             | component :: _ -> world, component
             | [] ->
                 invalid_arg "mk_query_iter1 expects at least one component")
         ~free:(fun _ -> ())
         (stage (fun (world, component) ->
              Query.iter1 world component (fun _ (_value : int) -> ()))))
    distribution_cases

let mk_query_iter2 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter2-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count ~component_count
                 ~distribution
             in
             match components with
             | c1 :: c2 :: _ -> world, c1, c2
             | _ -> invalid_arg "mk_query_iter2 expects at least two components")
         ~free:(fun _ -> ())
         (stage (fun (world, c1, c2) ->
              Query.iter2 world c1 c2 (fun _ (_v1 : int) (_v2 : int) -> ()))))
    distribution_cases

let mk_query_iter3 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter3-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count ~component_count
                 ~distribution
             in
             match components with
             | c1 :: c2 :: c3 :: _ -> world, c1, c2, c3
             | _ ->
                 invalid_arg "mk_query_iter3 expects at least three components")
         ~free:(fun _ -> ())
         (stage (fun (world, c1, c2, c3) ->
              Query.iter3 world c1 c2 c3
                (fun _ (_v1 : int) (_v2 : int) (_v3 : int) -> ()))))
    distribution_cases

let mk_query_iter4 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter4-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count ~component_count
                 ~distribution
             in
             match components with
             | c1 :: c2 :: c3 :: c4 :: _ -> world, c1, c2, c3, c4
             | _ ->
                 invalid_arg "mk_query_iter4 expects at least four components")
         ~free:(fun _ -> ())
         (stage (fun (world, c1, c2, c3, c4) ->
              Query.iter4 world c1 c2 c3 c4
                (fun _ (_v1 : int) (_v2 : int) (_v3 : int) (_v4 : int) -> ()))))
    distribution_cases

let mk_query_iter2_fragmented ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter2-fragmented-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count ~component_count
                 ~distribution
             in
             match components with
             | c1 :: c2 :: _ -> world, c1, c2
             | _ ->
                 invalid_arg
                   "mk_query_iter2_fragmented expects at least two components")
         ~free:(fun _ -> ())
         (stage (fun (world, c1, c2) ->
              Query.iter2 world c1 c2 (fun _ (_v1 : int) (_v2 : int) -> ()))))
    fragmented_distribution_cases

let mk_query_iter3_fragmented ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter3-fragmented-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count ~component_count
                 ~distribution
             in
             match components with
             | c1 :: c2 :: c3 :: _ -> world, c1, c2, c3
             | _ ->
                 invalid_arg
                   "mk_query_iter3_fragmented expects at least three components")
         ~free:(fun _ -> ())
         (stage (fun (world, c1, c2, c3) ->
              Query.iter3 world c1 c2 c3
                (fun _ (_v1 : int) (_v2 : int) (_v3 : int) -> ()))))
    fragmented_distribution_cases

let mk_query_iter_entities ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter_entities-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             Benchmark_helpers.populate_world ~entity_count ~component_count
               ~distribution)
         ~free:(fun _ -> ())
         (stage (fun (world, components) ->
              Query.iter_entities world components (fun _ -> ()))))
    distribution_cases

let mk_query_iter2_adversarial ~entity_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter2-adversarial-entities%d-%s" entity_count
           label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count
                 ~component_count:2 ~distribution
             in
             match components with
             | c1 :: c2 :: _ -> world, c1, c2
             | _ ->
                 invalid_arg
                   "mk_query_iter2_adversarial expects at least two components")
         ~free:(fun _ -> ())
         (stage (fun (world, c1, c2) ->
              Query.iter2 world c1 c2 (fun _ (_v1 : int) (_v2 : int) -> ()))))
    adversarial_distribution_cases

let mk_query_iter3_adversarial ~entity_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter3-adversarial-entities%d-%s" entity_count
           label
       in
       Test.make_with_resource ~name Test.uniq
         ~allocate:(fun () ->
             let world, components =
               Benchmark_helpers.populate_world ~entity_count
                 ~component_count:3 ~distribution
             in
             match components with
             | c1 :: c2 :: c3 :: _ -> world, c1, c2, c3
             | _ ->
                 invalid_arg
                   "mk_query_iter3_adversarial expects at least three components")
         ~free:(fun _ -> ())
         (stage (fun (world, c1, c2, c3) ->
              Query.iter3 world c1 c2 c3
                (fun _ (_v1 : int) (_v2 : int) (_v3 : int) -> ()))))
    adversarial_distribution_cases

let instances =
  [ Bechamel.Toolkit.Instance.monotonic_clock
  ; Bechamel.Toolkit.Instance.minor_allocated
  ; Bechamel.Toolkit.Instance.major_allocated
  ]

let run_and_report ~group_name suite =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  let raw =
    Benchmark.all cfg instances (Test.make_grouped ~name:group_name suite)
  in
  List.iter
    (fun instance ->
       let analyzed = Benchmark_helpers.analyze_single_instance instance raw in
       Benchmark_helpers.pp_results analyzed)
    instances

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

let mk_query_iter1 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter1-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make ~name
         (stage (fun () ->
              let world, components =
                Benchmark_helpers.populate_world
                  ~entity_count ~component_count ~distribution
              in
              match components with
              | component :: _ ->
                  fun () ->
                    Query.iter1 world component (fun _ (_value : int) -> ())
              | [] ->
                  invalid_arg "mk_query_iter1 expects at least one component")))
    distribution_cases

let mk_query_iter2 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter2-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make ~name
         (stage (fun () ->
              let world, components =
                Benchmark_helpers.populate_world
                  ~entity_count ~component_count ~distribution
              in
              match components with
              | c1 :: c2 :: _ ->
                  fun () ->
                    Query.iter2 world c1 c2 (fun _ (_v1: int) (_v2 : int) -> ())
              | _ ->
                  invalid_arg "mk_query_iter1 expects at least one component")))
    distribution_cases

let mk_query_iter3 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter3-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make ~name
         (stage (fun () ->
              let world, components =
                Benchmark_helpers.populate_world
                  ~entity_count ~component_count ~distribution
              in
              match components with
              | c1 :: c2 :: c3 :: _ ->
                  fun () ->
                    Query.iter3 world c1 c2 c3 (fun _ (_v1: int) (_v2 : int) (_v3 : int) -> ())
              | _ ->
                  invalid_arg "mk_query_iter1 expects at least one component")))
    distribution_cases

let mk_query_iter4 ~entity_count ~component_count =
  List.map
    (fun { label; distribution } ->
       let name =
         Printf.sprintf "query-iter4-entities%d-components%d-%s"
           entity_count component_count label
       in
       Test.make ~name
         (stage (fun () ->
              let world, components =
                Benchmark_helpers.populate_world
                  ~entity_count ~component_count ~distribution
              in
              match components with
              | c1 :: c2 :: c3 :: c4 :: _ ->
                  fun () ->
                    Query.iter4 world c1 c2 c3 c4 (fun _ (_v1: int) (_v2 : int) (_v3 : int) (_v4 : int) -> ())
              | _ ->
                  invalid_arg "mk_query_iter1 expects at least one component")))
    distribution_cases

let suite =
  Test.make_grouped ~name:"query_iter1"
    (List.concat
       [ mk_query_iter1 ~entity_count:10_000 ~component_count:1
       ; mk_query_iter1 ~entity_count:10_000 ~component_count:4
       ; mk_query_iter1 ~entity_count:50_000 ~component_count:4
       ; mk_query_iter2 ~entity_count:10_000 ~component_count:2
       ; mk_query_iter2 ~entity_count:10_000 ~component_count:4
       ; mk_query_iter2 ~entity_count:50_000 ~component_count:4
       ; mk_query_iter3 ~entity_count:10_000 ~component_count:3
       ; mk_query_iter3 ~entity_count:10_000 ~component_count:4
       ; mk_query_iter3 ~entity_count:50_000 ~component_count:4
       ; mk_query_iter4 ~entity_count:10_000 ~component_count:4
       ; mk_query_iter4 ~entity_count:10_000 ~component_count:6
       ; mk_query_iter4 ~entity_count:50_000 ~component_count:6

       ])

let instances =
  [ Bechamel.Toolkit.Instance.monotonic_clock
  ; Bechamel.Toolkit.Instance.minor_allocated
  ; Bechamel.Toolkit.Instance.major_allocated
  ]

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  let raw = Benchmark.all cfg instances suite in
  List.iter
    (fun instance ->
       let analyzed = Benchmark_helpers.analyze_single_instance instance raw in
       Benchmark_helpers.pp_results analyzed)
    instances

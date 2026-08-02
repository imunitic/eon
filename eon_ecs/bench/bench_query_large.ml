(* Large-scale query suite: entity_count > 10_000 (50k-1m), including the
   fragmented-iteration and sparse-set adversarial-worst-case workloads
   (ecs-047), which only matter at large scale. Split out from bench_query.ml
   because a combined run takes tens of minutes -- see the ecs-047 task note
   for context. Shared builders and distribution cases live in
   query_bench_defs.ml. *)
module D = Query_bench_defs

let suite =
  List.concat
    [ D.mk_query_iter1 ~entity_count:50_000 ~component_count:4
    ; D.mk_query_iter1 ~entity_count:100_000 ~component_count:4
    ; D.mk_query_iter1 ~entity_count:1_000_000 ~component_count:4
    ; D.mk_query_iter2 ~entity_count:50_000 ~component_count:4
    ; D.mk_query_iter2 ~entity_count:100_000 ~component_count:4
    ; D.mk_query_iter2 ~entity_count:1_000_000 ~component_count:4
    ; D.mk_query_iter3 ~entity_count:50_000 ~component_count:4
    ; D.mk_query_iter3 ~entity_count:100_000 ~component_count:4
    ; D.mk_query_iter3 ~entity_count:1_000_000 ~component_count:4
    ; D.mk_query_iter4 ~entity_count:50_000 ~component_count:6
    ; D.mk_query_iter4 ~entity_count:100_000 ~component_count:6
    ; D.mk_query_iter4 ~entity_count:1_000_000 ~component_count:6
    ; D.mk_query_iter_entities ~entity_count:50_000 ~component_count:4
    ; D.mk_query_iter_entities ~entity_count:100_000 ~component_count:4
    ; D.mk_query_iter_entities ~entity_count:1_000_000 ~component_count:4
    ; D.mk_query_iter2_fragmented ~entity_count:100_000 ~component_count:2
    ; D.mk_query_iter2_fragmented ~entity_count:1_000_000 ~component_count:2
    ; D.mk_query_iter3_fragmented ~entity_count:100_000 ~component_count:3
    ; D.mk_query_iter3_fragmented ~entity_count:1_000_000 ~component_count:3
    ; D.mk_query_iter2_adversarial ~entity_count:100_000
    ; D.mk_query_iter2_adversarial ~entity_count:1_000_000
    ; D.mk_query_iter3_adversarial ~entity_count:100_000
    ; D.mk_query_iter3_adversarial ~entity_count:1_000_000
    ]

let () = D.run_and_report ~group_name:"query_iter1_large" suite

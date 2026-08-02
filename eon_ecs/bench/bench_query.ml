(* Small/fast query suite: entity_count <= 10_000, for quick local iteration
   and as a fast CI step. See bench_query_large.ml for the 50k-1m variants
   (split out since the large sizes make a combined run take tens of
   minutes -- see the ecs-047 task note for context). Shared builders and
   distribution cases live in query_bench_defs.ml. *)
module D = Query_bench_defs

let suite =
  List.concat
    [ D.mk_query_iter1 ~entity_count:10_000 ~component_count:1
    ; D.mk_query_iter1 ~entity_count:10_000 ~component_count:4
    ; D.mk_query_iter2 ~entity_count:10_000 ~component_count:2
    ; D.mk_query_iter2 ~entity_count:10_000 ~component_count:4
    ; D.mk_query_iter3 ~entity_count:10_000 ~component_count:3
    ; D.mk_query_iter3 ~entity_count:10_000 ~component_count:4
    ; D.mk_query_iter4 ~entity_count:10_000 ~component_count:4
    ; D.mk_query_iter4 ~entity_count:10_000 ~component_count:6
    ; D.mk_query_iter_entities ~entity_count:10_000 ~component_count:1
    ; D.mk_query_iter_entities ~entity_count:10_000 ~component_count:2
    ; D.mk_query_iter_entities ~entity_count:10_000 ~component_count:4
    ]

let () = D.run_and_report ~group_name:"query_iter1" suite

(* Cached_backend vs. Sparse_set_backend on the sparse-set adversarial
   worst-case workload from ecs-047's BENCHMARKS.md (two components at
   ~0.1% presence each, drawn independently so their intersection is close
   to empty). This is the actual point of ecs-050: a query signature run
   every frame (simulated here as [cycles] repeated calls against an
   unchanging world) should go from "rescan the smallest set every call"
   to "serve the cached match list every call after the first."

   Uses Test.uniq (one world+cache reused across all timed calls, per
   Bechamel's real allocate/free semantics -- see the second brain's
   Bechamel Staged.stage note) since this workload is explicitly about
   repeated queries against unchanging state, unlike the one-shot
   "consume" workloads elsewhere in this repo that need Test.multiple. *)

open Bechamel
open Staged

module World = Eon_engine.World
module Components = Eon_engine.Components
module Sparse_set_backend = Eon_engine.Sparse_set_backend
module Cached_backend = Eon_engine.Cached_backend
module Query = Eon_engine.Query

module P = struct
  type t = int
  let component : t Components.t = Components.component "P"
end

module Q_comp = struct
  type t = int
  let component : t Components.t = Components.component "Q"
end

let populate_adversarial ~entity_count ~probability =
  let world = World.create () in
  ignore (World.register world P.component);
  ignore (World.register world Q_comp.component);
  let state = Random.State.make [| 0xADEC5; entity_count |] in
  for _ = 1 to entity_count do
    let e = World.create_entity world in
    if Random.State.float state 1.0 <= probability then
      World.add_component world e P.component 0;
    if Random.State.float state 1.0 <= probability then
      World.add_component world e Q_comp.component 0
  done;
  world

module QDirect = Query.Make (Sparse_set_backend.Default)

let mk_uncached ~entity_count ~cycles =
  let name =
    Printf.sprintf "adversarial-uncached-entities%d-cyc%d" entity_count cycles
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () -> populate_adversarial ~entity_count ~probability:0.001)
    ~free:(fun _ -> ())
    (stage (fun world ->
         for _ = 1 to cycles do
           ignore
             (QDirect.from world |> QDirect.having P.component
              |> QDirect.having Q_comp.component |> QDirect.count
              : int)
         done))

let mk_cached ~entity_count ~cycles =
  let name =
    Printf.sprintf "adversarial-cached-entities%d-cyc%d" entity_count cycles
  in
  (* A fresh functor application per test variant -- Cached_backend's cache
     is module-level state created once at instantiation, so sharing one
     Cached_backend module across the 100k and 1M variants (same
     ["P";"Q"] cache key) would leak one variant's cache entry into the
     other's. *)
  let module QCached =
    Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default))
  in
  Test.make_with_resource ~name Test.uniq
    ~allocate:(fun () ->
        let world = populate_adversarial ~entity_count ~probability:0.001 in
        QCached.cache_signature ~required:["P"; "Q"] ~excludes:[];
        world)
    ~free:(fun _ -> ())
    (stage (fun world ->
         for _ = 1 to cycles do
           ignore
             (QCached.from world |> QCached.having P.component
              |> QCached.having Q_comp.component |> QCached.count
              : int)
         done))

let suite =
  Test.make_grouped ~name:"cached_backend"
    [ mk_uncached ~entity_count:100_000 ~cycles:100
    ; mk_cached ~entity_count:100_000 ~cycles:100
    ; mk_uncached ~entity_count:1_000_000 ~cycles:100
    ; mk_cached ~entity_count:1_000_000 ~cycles:100
    ]

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  Benchmark_helpers.bench_with_gc cfg suite;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."

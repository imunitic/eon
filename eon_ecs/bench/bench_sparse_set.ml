open Bechamel
open Bechamel.Toolkit
open Staged

module Sparse_set = Eon_ecs__Sparse_set
module Entity_id = Eon_ecs__Entity_id

(* Blueprint benchmark focusing on steady add/remove workloads over a sparse set. *)

let int_entities count =
  Array.init count (fun i -> (Entity_id.make i 0, i))

let mk_sparse_set_add_remove count =
  let precomputed = int_entities count in
  Test.make ~name:(Printf.sprintf "add/remove-%d" count)
    (stage (fun () ->
         let set = Sparse_set.create () in
         Array.iter
           (fun (entity, value) ->
             (* add followed by immediate remove exercises both hot paths *)
             Sparse_set.add set entity value;
             Sparse_set.remove set entity)
           precomputed))

let sparse_set_suite =
  Test.make_grouped ~name:"sparse_set"
    [ mk_sparse_set_add_remove 1_000
    ; mk_sparse_set_add_remove 10_000
    ]

let instances =
  [ Toolkit.Instance.monotonic_clock ]

let benchmark cfg =
  Benchmark.all cfg instances sparse_set_suite

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  let raw = benchmark cfg in
  let analyzed =
    Benchmark_helpers.analyze_single_instance Toolkit.Instance.monotonic_clock
      raw
  in
  Benchmark_helpers.pp_results analyzed;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."

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

let mk_sparse_set_update_in_place count =
  let precomputed = int_entities count in
  let set = Sparse_set.create () in
  Array.iter (fun (entity, value) -> Sparse_set.add set entity value) precomputed;
  Test.make ~name:(Printf.sprintf "update-in-place-%d" count)
    (stage (fun () ->
         Array.iter
           (fun (entity, value) ->
             Sparse_set.set_value set entity (value + 1) )
           precomputed))

let mk_sparse_set_iter count =
  let precomputed = int_entities count in
  let set = Sparse_set.create () in
  Array.iter (fun (entity, value) -> Sparse_set.add set entity value) precomputed;
  Test.make ~name:(Printf.sprintf "iter-%d" count)
    (stage (fun () ->
         Sparse_set.iter (fun _ _ -> ()) set))

let mk_sparse_set_grow count =
  let precomputed = int_entities count in
  Test.make ~name:(Printf.sprintf "grow-%d" count)
    (stage (fun () ->
         let set = Sparse_set.create () in
         Array.iter (fun (e, v) -> Sparse_set.add set e v) precomputed))

let mk_sparse_set_prefill count =
  let precomputed = int_entities count in
   Test.make ~name:(Printf.sprintf "prefill-%d" count)
    (stage (fun () ->
         let set = Sparse_set.create ~capacity:count () in
         Array.iter (fun (e, v) -> Sparse_set.add set e v) precomputed))

let mk_sparse_set_get count =
  let precomputed = int_entities count in
  let set = Sparse_set.create () in
  Array.iter (fun (e, v) -> Sparse_set.add set e v) precomputed;
  let existing = Array.sub precomputed 0 (count / 2) in
  let missing = Array.init (count / 2) (fun i -> (Entity_id.make (count + i) 0, i)) in
  let mixed = Array.append existing missing in
  Test.make ~name:(Printf.sprintf "get-mixed-%d" count)
    (stage (fun () ->
         Array.iter (fun (e, _) -> ignore (Sparse_set.get set e)) mixed))

let mk_sparse_set_remove_existing count =
  let precomputed = int_entities count in
  let set = Sparse_set.create ~capacity:count () in
  Test.make ~name:(Printf.sprintf "remove-existing-%d" count)
    (stage (fun () ->
       Array.iter (fun (e, v) -> Sparse_set.add set e v) precomputed;
       Array.iter (fun (e, _) -> Sparse_set.remove set e) precomputed))

let mk_sparse_set_remove_missing count =
  let precomputed = int_entities count in
  let set = Sparse_set.create () in
  Test.make ~name:(Printf.sprintf "remove-missing-%d" count)
    (stage (fun () ->
         Array.iter (fun (e, _) -> Sparse_set.remove set e) precomputed))

let mk_sparse_set_churn count =
  let ids = Array.init count (fun i -> (Entity_id.make i 0, i)) in
  let set = Sparse_set.create ~capacity:count () in
  Test.make ~name:(Printf.sprintf "churn-%d" count)
(stage (fun () ->
     Array.iter (fun (e,v) -> Sparse_set.add set e v) ids;
     for i = 0 to (count / 2) - 1 do
       let e, _ = ids.(i) in
       Sparse_set.remove set e
     done;
     Array.iter (fun (e,v) -> Sparse_set.add set e v) ids))

let sparse_set_suite =
  Test.make_grouped ~name:"sparse_set"
    [ mk_sparse_set_add_remove 1_000
    ; mk_sparse_set_add_remove 10_000
    ; mk_sparse_set_update_in_place 1_000
    ; mk_sparse_set_update_in_place 10_000
    ; mk_sparse_set_iter 1_000
    ; mk_sparse_set_iter 10_000
    ; mk_sparse_set_grow 1_000
    ; mk_sparse_set_grow 10_000
    ; mk_sparse_set_prefill 1_000
    ; mk_sparse_set_prefill 10_000
    ; mk_sparse_set_get 1_000
    ; mk_sparse_set_get 10_000
    ; mk_sparse_set_remove_existing 1_000
    ; mk_sparse_set_remove_existing 10_000
    ; mk_sparse_set_remove_missing 1_000
    ; mk_sparse_set_remove_missing 10_000
    ; mk_sparse_set_churn 1_000
    ; mk_sparse_set_churn 10_000
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

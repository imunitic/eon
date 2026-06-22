open Bechamel
open Bechamel.Toolkit
open Staged
open Eon_engine

(* Pools instantiated once — measures steady-state run_all cost, not pool creation *)
module P4   = Executor.Domain_pool.Make(struct let size = 4 end)
module Prec = Executor.Domain_pool.Make(struct
  let size = Executor.Domain_pool.recommended_size ()
end)

(* ------------------------------------------------------------------ *)
(* Q1: Raw pool overhead — no-op jobs                                  *)
(*                                                                      *)
(* Measures the fixed cost of run_all itself: mutex, condition,        *)
(* queue round-trip. The jobs do nothing; any time measured here is    *)
(* pure executor overhead. Shows the "tax" per run_all call.           *)
(* ------------------------------------------------------------------ *)

let mk_noop_seq n =
  let jobs = List.init n (fun _ -> fun () -> ()) in
  Test.make ~name:(Printf.sprintf "sequential/noop-jobs-%d" n)
    (stage (fun () -> Executor.Sequential.run_all jobs))

let mk_noop_pool n =
  let jobs = List.init n (fun _ -> fun () -> ()) in
  Test.make ~name:(Printf.sprintf "domain_pool_4/noop-jobs-%d" n)
    (stage (fun () -> P4.run_all jobs))

let overhead_suite =
  Test.make_grouped ~name:"overhead"
    [ mk_noop_seq  1; mk_noop_pool  1
    ; mk_noop_seq  4; mk_noop_pool  4
    ; mk_noop_seq  8; mk_noop_pool  8
    ; mk_noop_seq 16; mk_noop_pool 16
    ]

(* ------------------------------------------------------------------ *)
(* Q2: Crossover — medium-cost compute job                             *)
(*                                                                      *)
(* Each job folds over a 10k int array. Sweeping job count shows at    *)
(* which N the parallelism gain overtakes the pool overhead.           *)
(* ------------------------------------------------------------------ *)

let fold_arr = Array.init 10_000 Fun.id

let compute_job () = ignore (Array.fold_left ( + ) 0 fold_arr)

let mk_compute_seq n =
  let jobs = List.init n (fun _ -> compute_job) in
  Test.make ~name:(Printf.sprintf "sequential/compute-jobs-%d" n)
    (stage (fun () -> Executor.Sequential.run_all jobs))

let mk_compute_pool n =
  let jobs = List.init n (fun _ -> compute_job) in
  Test.make ~name:(Printf.sprintf "domain_pool_4/compute-jobs-%d" n)
    (stage (fun () -> P4.run_all jobs))

let crossover_suite =
  Test.make_grouped ~name:"crossover"
    [ mk_compute_seq  1; mk_compute_pool  1
    ; mk_compute_seq  2; mk_compute_pool  2
    ; mk_compute_seq  4; mk_compute_pool  4
    ; mk_compute_seq  8; mk_compute_pool  8
    ; mk_compute_seq 16; mk_compute_pool 16
    ]

(* ------------------------------------------------------------------ *)
(* Q3: ECS scale — 8 parallel systems each processing 500 entities     *)
(*                                                                      *)
(* Each job owns independent position/velocity arrays — no sharing,    *)
(* matching the real ECS guarantee that parallel systems do not share  *)
(* component data. The update is a tight per-entity float arithmetic   *)
(* loop, representative of physics/animation systems.                  *)
(*                                                                      *)
(* Compared at pool size 4 and recommended_size() to show scaling.     *)
(* ------------------------------------------------------------------ *)

let entity_count  = 500
let system_count  = 8
let dt            = 1.0 /. 60.0

let positions  = Array.init system_count (fun _ -> Array.make entity_count (0.0, 0.0))
let velocities = Array.init system_count (fun _ -> Array.make entity_count (1.0, 0.5))

let make_physics_job system_idx =
  fun () ->
    let pos = positions.(system_idx) in
    let vel = velocities.(system_idx) in
    for i = 0 to entity_count - 1 do
      let x, y  = pos.(i) in
      let vx, vy = vel.(i) in
      pos.(i) <- (x +. vx *. dt, y +. vy *. dt)
    done

let ecs_jobs = List.init system_count make_physics_job

let ecs_suite =
  Test.make_grouped ~name:"ecs_scale"
    [ Test.make ~name:"sequential/ecs-8x500"
        (stage (fun () -> Executor.Sequential.run_all ecs_jobs))
    ; Test.make ~name:"domain_pool_4/ecs-8x500"
        (stage (fun () -> P4.run_all ecs_jobs))
    ; Test.make ~name:"domain_pool_rec/ecs-8x500"
        (stage (fun () -> Prec.run_all ecs_jobs))
    ]

(* ------------------------------------------------------------------ *)

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  Format.printf "=== Q1: Pool overhead (no-op jobs) ===@.";
  Benchmark_helpers.bench_with_gc cfg overhead_suite;
  Format.printf "@.=== Q2: Crossover point (compute jobs) ===@.";
  Benchmark_helpers.bench_with_gc cfg crossover_suite;
  Format.printf "@.=== Q3: ECS scale (8 systems x 500 entities) ===@.";
  Format.printf "(domain_pool_rec pool size: %d)@."
    (Executor.Domain_pool.recommended_size ());
  Benchmark_helpers.bench_with_gc cfg ecs_suite

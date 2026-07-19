open Eon_engine

(* [Domain_pool.Make(Config)] spawns [Config.size] real OS domains once at
   module instantiation and never tears them down — there is no [shutdown]
   in the exposed [S] signature, the worker loop only exits if its internal
   [shutdown] ref is set, which nothing public ever does. Randomizing pool
   *size* per QCheck iteration would therefore leak a real OS domain per
   iteration for the lifetime of the test process (hundreds of iterations x
   even a small size = hundreds of permanently-blocked domains). Instead:
   instantiate a small, fixed set of pools once here, and randomize only the
   job count against them — still exercises multiple concurrency levels,
   without leaking unboundedly. *)
module Pool1 = Executor.Domain_pool.Make (struct let size = 1 end)
module Pool2 = Executor.Domain_pool.Make (struct let size = 2 end)
module Pool4 = Executor.Domain_pool.Make (struct let size = 4 end)

let run_all_of_pool = function
  | 0 -> Pool1.run_all
  | 1 -> Pool2.run_all
  | _ -> Pool4.run_all

let pool_label = function 0 -> "size=1" | 1 -> "size=2" | _ -> "size=4"

let gen_case =
  let open QCheck.Gen in
  let* pool_idx = int_range 0 2 in
  let* job_count = int_range 0 150 in
  return (pool_idx, job_count)

let pp_case (pool_idx, job_count) =
  Printf.sprintf "pool=%s job_count=%d" (pool_label pool_idx) job_count

let arb_case = QCheck.make ~print:pp_case gen_case

let prop_every_job_runs_exactly_once =
  let test_fn (pool_idx, job_count) =
    let counters = Array.init job_count (fun _ -> Atomic.make 0) in
    let jobs = List.init job_count (fun i -> fun () -> Atomic.incr counters.(i)) in
    (run_all_of_pool pool_idx) jobs;
    Array.for_all (fun c -> Atomic.get c = 1) counters
  in
  QCheck.Test.make
    ~name:"Executor.Domain_pool: every job runs exactly once, across job counts and pool sizes"
    ~count:150 arb_case test_fn

let tests = [ QCheck_alcotest.to_alcotest prop_every_job_runs_exactly_once ]

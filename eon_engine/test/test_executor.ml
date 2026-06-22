open Eon_engine

let test_sequential_run_all () =
  let order = ref [] in
  let jobs = List.init 4 (fun i -> fun () -> order := i :: !order) in
  Executor.Sequential.run_all jobs;
  Alcotest.(check (list int)) "sequential order" [3; 2; 1; 0] !order

let test_sequential_empty () =
  Executor.Sequential.run_all [];
  Alcotest.(check pass) "empty returns" () ()

let test_domain_pool_run_all () =
  let module P = Executor.Domain_pool.Make(struct let size = 4 end) in
  let mutex = Mutex.create () in
  let results = ref [] in
  let n = 20 in
  let jobs =
    List.init n (fun i ->
      fun () ->
        Mutex.protect mutex (fun () -> results := i :: !results))
  in
  P.run_all jobs;
  let sorted = List.sort Int.compare !results in
  Alcotest.(check (list int)) "all jobs ran"
    (List.init n Fun.id) sorted

let test_domain_pool_empty () =
  let module P = Executor.Domain_pool.Make(struct let size = 2 end) in
  P.run_all [];
  Alcotest.(check pass) "empty returns" () ()

let test_domain_pool_exception () =
  let module P = Executor.Domain_pool.Make(struct let size = 2 end) in
  let counter = Atomic.make 0 in
  let jobs =
    List.init 4 (fun i ->
      fun () ->
        Atomic.incr counter;
        if i = 2 then raise Exit)
  in
  (match P.run_all jobs with
   | exception Exit -> ()
   | _ -> Alcotest.fail "expected Exit to be re-raised");
  Alcotest.(check int) "all jobs still ran" 4 (Atomic.get counter)

let test_domain_pool_concurrent () =
  let module P = Executor.Domain_pool.Make(struct let size = 4 end) in
  let n = 100 in
  let counter = Atomic.make 0 in
  let jobs = List.init n (fun _ -> fun () -> Atomic.incr counter) in
  P.run_all jobs;
  Alcotest.(check int) "counter reached n" n (Atomic.get counter)

let test_recommended_size () =
  let size = Executor.Domain_pool.recommended_size () in
  Alcotest.(check bool) "at least 1" true (size >= 1)

let tests = [
  "sequential run_all",       `Quick, test_sequential_run_all;
  "sequential empty",         `Quick, test_sequential_empty;
  "domain_pool run_all",      `Quick, test_domain_pool_run_all;
  "domain_pool empty",        `Quick, test_domain_pool_empty;
  "domain_pool exception",    `Quick, test_domain_pool_exception;
  "domain_pool concurrent",   `Quick, test_domain_pool_concurrent;
  "recommended_size >= 1",    `Quick, test_recommended_size;
]

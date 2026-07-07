open Bechamel
open Staged
open Eon_engine


(* Pre-warm a stream to N capacity, then clear it so it starts empty but
   with the backing array already allocated. *)
let make_warm_stream n =
  let s = Render_stream.create () in
  for i = 1 to n do Render_stream.add_world s i done;
  Render_stream.clear s;
  s

(* ------------------------------------------------------------------ *)
(* Q1: Steady-state frame cycle                                        *)
(*                                                                     *)
(* Each run: add N commands → iterate → clear.                        *)
(* The stream is pre-warmed so Dynarray never needs to grow.          *)
(* minor_allocated should be 0 at steady state.                       *)
(* ------------------------------------------------------------------ *)

let mk_frame_warm n =
  let s = make_warm_stream n in
  Test.make ~name:(Printf.sprintf "frame-warm/%d" n) (stage (fun () ->
    for i = 1 to n do Render_stream.add_world s i done;
    Render_stream.iter_world s ignore;
    Render_stream.clear s))

let frame_suite =
  Test.make_grouped ~name:"frame_cycle"
    [ mk_frame_warm   50
    ; mk_frame_warm  200
    ; mk_frame_warm  500
    ; mk_frame_warm 1000
    ]

(* ------------------------------------------------------------------ *)
(* Q2: add_world throughput                                           *)
(*                                                                     *)
(* N adds per run on a pre-warmed stream that is NOT cleared between  *)
(* runs. The benchmark harness runs the stage many times; by run 2    *)
(* the adds overflow the pre-warmed capacity and trigger growth.      *)
(* This is intentional — it shows the amortised cost of Dynarray      *)
(* growth vs the O(1) add when capacity is sufficient.                *)
(*                                                                     *)
(* Compare with frame_cycle which clears before each run: the         *)
(* steady-state add cost there is always within-capacity.             *)
(* ------------------------------------------------------------------ *)

let mk_add_only n =
  let s = make_warm_stream n in
  Test.make ~name:(Printf.sprintf "add-only/%d" n) (stage (fun () ->
    for i = 1 to n do Render_stream.add_world s i done))

let add_suite =
  Test.make_grouped ~name:"add_world"
    [ mk_add_only   50
    ; mk_add_only  200
    ; mk_add_only  500
    ; mk_add_only 1000
    ]

(* ------------------------------------------------------------------ *)
(* Q3: iter_world throughput                                          *)
(*                                                                     *)
(* Stream pre-filled and never modified. Each run iterates the whole  *)
(* world list. Isolates cache and traversal cost from allocation.     *)
(* minor_allocated must be 0 — iteration never allocates.             *)
(* ------------------------------------------------------------------ *)

let mk_iter_only n =
  let s = Render_stream.create () in
  for i = 1 to n do Render_stream.add_world s i done;
  Test.make ~name:(Printf.sprintf "iter-only/%d" n) (stage (fun () ->
    Render_stream.iter_world s ignore))

let iter_suite =
  Test.make_grouped ~name:"iter_world"
    [ mk_iter_only   50
    ; mk_iter_only  200
    ; mk_iter_only  500
    ; mk_iter_only 1000
    ]

(* ------------------------------------------------------------------ *)

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Bechamel.Time.second 1.0) () in
  Format.printf "=== Q1: Steady-state frame cycle (pre-warmed Dynarray) ===@.";
  Format.printf "  minor_allocated should be 0 at all sizes@.@.";
  Benchmark_helpers.bench_with_gc cfg frame_suite;
  Format.printf "@.=== Q2: add_world throughput ===@.";
  Benchmark_helpers.bench_with_gc cfg add_suite;
  Format.printf "@.=== Q3: iter_world throughput (read-only, no allocation) ===@.";
  Benchmark_helpers.bench_with_gc cfg iter_suite

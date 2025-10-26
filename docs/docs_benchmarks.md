# 🧪 Benchmark Blueprint (Bechamel)

This note captures the pattern we use for performance benchmarks.

## 🔧 Example: `bench_sparse_set.ml`

```ocaml
open Bechamel
open Bechamel.Toolkit
open Staged

module Sparse_set = Eon_ecs__Sparse_set
(* For non-entity keys you can spin up a specialised set with
   [module Int_set = Sparse_set.Make(struct type t = int let index x = x end)]. *)
module Entity_id  = Eon_ecs__Entity_id

let int_entities count =
  Array.init count (fun i -> (Entity_id.make i 0, i))

let mk_sparse_set_add_remove count =
  let precomputed = int_entities count in
  Test.make ~name:(Printf.sprintf "add/remove-%d" count)
    (stage (fun () ->
         let set = Sparse_set.create () in
         Array.iter
           (fun (entity, value) ->
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
    Benchmark_helpers.analyze_single_instance Toolkit.Instance.monotonic_clock raw
  in
  Benchmark_helpers.pp_results analyzed;
  Format.printf "@.Hint: use this file as a template when adding more benches.@."
```

## 🧩 Key points

- `Staged.stage` ensures each run gets a fresh data structure.
- Precompute workloads so we only measure the target API.
- Group variant sizes (`1_000`, `10_000`) to compare scaling.
- Use `Toolkit.Instance.*` for metrics (monotonic clock, allocations, …).
- Feed results through `Benchmark_helpers.analyze_single_instance` and print using `Benchmark_helpers.pp_results` for consistency across benches.

## ▶️ Running

```sh
opam install bechamel  # one-time setup

dune exec eon_ecs/bench/bench_sparse_set.exe --profile=release
```

## 🏗️ Building Query Worlds for Benches

`Benchmark_helpers` exposes utilities for building synthetic worlds:

```ocaml
val register_components : World.t -> string list -> unit
val populate_world :
  ?distribution:(int -> int -> bool) ->
  entity_count:int -> component_count:int -> World.t * string list
```

You can pick from the bundled distributions or supply your own:

```ocaml
val default_distribution : int -> int -> bool
val distribution_all : int -> int -> bool
val distribution_every : int -> (int -> int -> bool)
val distribution_alternating : int -> int -> bool
val distribution_random : ?seed:int -> probability:float -> unit -> int -> int -> bool
val distribution_gradient : period:int -> peak:int -> int -> int -> bool
```

Example usage:

```ocaml
let world, _ =
  Benchmark_helpers.populate_world
    ~entity_count:10_000 ~component_count:3
    ~distribution:(Benchmark_helpers.distribution_every 3)
```

All helpers are deterministic unless you opt into `distribution_random` (which accepts an optional `~seed`).

## ✅ TODO — Future Benchmarks

- [ ] Component registry + world component attach/remove cycles
- [ ] Query iterators (`iter1`, `iter2`, …) over varying tuple widths and populations
- [ ] Bus emit/collect/drain throughput (`Single_bus`, `Double_bus`)
- [ ] Resource_store service/data get/set loops (post-variant keys)
- [ ] Pipeline registration + `run_by_filter` scheduling overhead
- [ ] Progress controller (`tick` in variable/fixed/hybrid modes)
- [ ] Full loop step orchestration with stub systems/buses

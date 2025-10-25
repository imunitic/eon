# 🧪 Benchmark Blueprint (Bechamel)

This note captures the pattern we use for performance benchmarks.

## 🔧 Example: `bench_sparse_set.ml`

```ocaml
open Bechamel
open Bechamel.Toolkit
open Staged

module Sparse_set = Eon_ecs__Sparse_set
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

```ocaml
let register_components world names =
  List.iteri (fun id name -> ignore (World.register_component world ~name ~id)) names

let populate_world ~entity_count ~component_count =
  let world = World.create () in
  let names =
    List.init component_count (fun i -> Printf.sprintf "C%d" (i + 1))
  in
  register_components world names;

  for eid = 0 to entity_count - 1 do
    let entity = World.create_entity world in
    List.iteri
      (fun idx name ->
         if eid mod (idx + 2) = 0 then
           World.add_component world entity ~name (eid + idx))
      names
  done;
  world, names
```

- `component_count` maps to the arity you want (`iter1` … `iter6`).
- Adjust the modulo rule or use a seeded RNG to control overlap density.
- Precompute once; stage the `Query.iterN` call just like the sparse-set example.

## ✅ TODO — Future Benchmarks

- [ ] Component registry + world component attach/remove cycles
- [ ] Query iterators (`iter1`, `iter2`, …) over varying tuple widths and populations
- [ ] Bus emit/collect/drain throughput (`Single_bus`, `Double_bus`)
- [ ] Resource_store service/data get/set loops (post-variant keys)
- [ ] Pipeline registration + `run_by_filter` scheduling overhead
- [ ] Progress controller (`tick` in variable/fixed/hybrid modes)
- [ ] Full loop step orchestration with stub systems/buses

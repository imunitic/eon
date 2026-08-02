# eon_ecs Benchmarks

Real numbers from `just bench <name>` (release profile), run on the machine described in
[Environment](#environment). One column only — `eon_ecs` against itself, not against other ECS
libraries. See [Methodology](#methodology) for why, and how these numbers were arrived at.

## Environment

| | |
|---|---|
| Machine | Apple M2, 16 GB RAM |
| OS | macOS 26.5.2 (Darwin 25.5.0) |
| OCaml | 5.5.0 |
| Dune | 3.15 |
| Bechamel | 0.5.0 |
| Config | `Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) ()` |
| Metrics collected | `monotonic_clock` (time/run, shown below), `minor_allocated`, `major_allocated` |

`time/run` is nanoseconds per timed call, as reported by Bechamel's OLS analysis
(`Benchmark_helpers.analyze_single_instance`/`pp_results`). Every workload below with a `cycles`,
`~` batch, or explicit op count folded into the timing is called out per-row.

## Workload table

Grouped by the SkyECS-derived taxonomy from `ecs-047`'s task note. One representative distribution
("default") is shown per size for the general iteration/access workloads; the deliberately-scoped
fragmented/adversarial workloads are shown in full.

### Bulk / single insert

`eon_ecs` has one entity-creation path (`create_entity` + `add_component` per component, no batch
API) — bulk and single insert collapse into one shape; `component_count = 1` is "single insert."

| Workload | Entities | Components | time/run | ns/entity |
|---|---:|---:|---:|---:|
| bulk-insert | 10,000 | 1 | 4.638e+05 ns | 46.4 |
| bulk-insert | 10,000 | 4 | 2.203e+06 ns | 220.3 |
| bulk-insert | 100,000 | 4 | 2.097e+07 ns | 209.7 |
| bulk-insert | 1,000,000 | 4 | 2.359e+08 ns | 235.9 |

Scales linearly with entity count, as expected — no batch API means no amortization to lose.

### Prepared iteration (`Query.iter1`–`iter4`, `iter_entities`)

World population happens once per test (outside the timed portion — see
[Methodology](#methodology)); only the query call itself is timed. "default" distribution:
`eid mod (idx + 2) = 0` (component `idx` present on roughly `1/(idx+2)` of entities).

| Workload | Entities | Components | time/run |
|---|---:|---:|---:|
| iter1 | 10,000 | 1 | 2.313e+04 ns |
| iter1 | 10,000 | 4 | 2.138e+04 ns |
| iter1 | 50,000 | 4 | 1.061e+05 ns |
| iter1 | 100,000 | 4 | 2.123e+05 ns |
| iter1 | 1,000,000 | 4 | 2.116e+06 ns |
| iter2 | 10,000 | 2 | 3.185e+04 ns |
| iter2 | 10,000 | 4 | 3.264e+04 ns |
| iter2 | 50,000 | 4 | 1.558e+05 ns |
| iter2 | 100,000 | 4 | 3.013e+05 ns |
| iter2 | 1,000,000 | 4 | 3.274e+06 ns |
| iter3 | 10,000 | 3 | 2.879e+04 ns |
| iter3 | 10,000 | 4 | 2.905e+04 ns |
| iter3 | 50,000 | 4 | 1.430e+05 ns |
| iter3 | 100,000 | 4 | 2.877e+05 ns |
| iter3 | 1,000,000 | 4 | 3.200e+06 ns |
| iter4 | 10,000 | 4 | 1.723e+04 ns |
| iter4 | 10,000 | 6 | 1.724e+04 ns |
| iter4 | 50,000 | 6 | 8.530e+04 ns |
| iter4 | 100,000 | 6 | 1.733e+05 ns |
| iter4 | 1,000,000 | 6 | 2.733e+06 ns |
| iter_entities | 10,000 | 1 | 2.363e+04 ns |
| iter_entities | 10,000 | 4 | 2.050e+04 ns |
| iter_entities | 50,000 | 4 | 9.983e+04 ns |
| iter_entities | 100,000 | 4 | 2.019e+05 ns |
| iter_entities | 1,000,000 | 4 | 2.247e+06 ns |

Distribution shape matters more than arity at a fixed size: `iter2` at 10,000 entities/4 components
ranges from 2.581e+04 ns (`every-5`, sparse) to 1.315e+05 ns (`all`, every entity matches) across the
suite's 7 distribution cases — a ~5x spread from density alone, before touching size or arity. The
full per-distribution breakdown is in the raw `just bench query`/`query_large` output, not reproduced
here in full.

### Fragmented iteration

Each component in the signature draws membership independently at a low, shared probability (5% or
1%) — a multi-component query's match count shrinks geometrically with arity even though no single
component's sparse set is tiny. Less extreme than the dedicated adversarial worst case below.

| Workload | Entities | Distribution | time/run |
|---|---:|---|---:|
| iter2-fragmented | 100,000 | p=5% | 4.981e+04 ns |
| iter2-fragmented | 100,000 | p=1% | 5.767e+03 ns |
| iter2-fragmented | 1,000,000 | p=5% | 3.872e+05 ns |
| iter2-fragmented | 1,000,000 | p=1% | 9.572e+04 ns |
| iter3-fragmented | 100,000 | p=5% | 3.607e+04 ns |
| iter3-fragmented | 100,000 | p=1% | 5.938e+03 ns |
| iter3-fragmented | 1,000,000 | p=5% | 3.803e+05 ns |
| iter3-fragmented | 1,000,000 | p=1% | 1.205e+05 ns |

### Sparse-set adversarial worst case

Not in SkyECS — added deliberately (see [Methodology](#methodology)). Two/three components each
present on ~0.1% of the world, drawn independently so their intersection is close to empty. The
smallest involved sparse set is hundreds to low thousands of entities in absolute terms, but the scan
rejects almost every candidate it walks. **This is the baseline `ecs-050`'s `Cached_backend` is
measured against.**

| Workload | Entities | time/run |
|---|---:|---:|
| iter2-adversarial | 100,000 | 6.065e+02 ns |
| iter2-adversarial | 1,000,000 | 9.836e+03 ns |
| iter3-adversarial | 100,000 | 7.597e+02 ns |
| iter3-adversarial | 1,000,000 | 7.186e+03 ns |

Note these are *fast in absolute time* (the smallest set is only ~100–1,000 entities even at 1M
scale) — the pathology is wasted work relative to yield (near-zero matches per scan), not raw
latency. A repeated per-frame query against a signature like this is what `Cached_backend` turns
from "rescan the smallest set every frame" into "return the cached match list, refill only on
`component_generation` mismatch."

### Prepared random access (`World.get_component`)

`hit`: all entities carry the component. `mixed`: alternating present/absent. `random50`: ~50%
present, uniformly random. `clustered`: first half present, second half absent (same 50% rate as
`random50`, but contiguous). Each row folds `cycles` full passes over the entity array into one
timed call — see the per-row cycle count.

| Workload | Entities | Cycles | time/run | ns/op |
|---|---:|---:|---:|---:|
| hit | 1,000 | 10 | 1.817e+05 ns | 18.2 |
| hit | 10,000 | 5 | 9.046e+05 ns | 18.1 |
| hit | 100,000 | 2 | 3.634e+06 ns | 18.2 |
| hit | 1,000,000 | 1 | 1.829e+07 ns | 18.3 |
| mixed | 1,000 | 10 | 1.780e+05 ns | 17.8 |
| mixed | 10,000 | 5 | 9.067e+05 ns | 18.1 |
| mixed | 100,000 | 2 | 3.771e+06 ns | 18.9 |
| mixed | 1,000,000 | 1 | 1.794e+07 ns | 17.9 |
| random50 | 1,000 | 10 | 2.282e+05 ns | 22.8 |
| random50 | 10,000 | 5 | 1.165e+06 ns | 23.3 |
| random50 | 100,000 | 2 | 4.610e+06 ns | 23.1 |
| random50 | 1,000,000 | 1 | 2.256e+07 ns | 22.6 |
| clustered | 1,000 | 10 | 1.783e+05 ns | 17.8 |
| clustered | 10,000 | 5 | 8.951e+05 ns | 17.9 |
| clustered | 100,000 | 2 | 3.576e+06 ns | 17.9 |
| clustered | 1,000,000 | 1 | 1.824e+07 ns | 18.2 |

`random50`'s ~25% higher per-op cost than the other three is consistent across every size — the
uniformly-random present/absent pattern defeats branch prediction/prefetching in a way the
contiguous `clustered` split (same 50% rate) doesn't.

### Spawn / random despawn

Entities and a full deterministic destroy-order shuffle are prepared once per timed call (outside
timing); only the destroy pass itself is measured.

| Workload | Entities | time/run | ns/entity |
|---|---:|---:|---:|
| despawn-only | 10,000 | 2.012e+05 ns | 20.1 |
| despawn-only | 100,000 | 2.167e+06 ns | 21.7 |
| despawn-only | 1,000,000 | 3.563e+07 ns | 35.6 |

### Random add/remove component churn

Two independent deterministic permutations (insert order, removal order); the timed call is one
full add-pass followed by one full remove-pass.

| Workload | Entities | time/run | ns/op |
|---|---:|---:|---:|
| random-add-remove | 10,000 | 4.267e+05 ns | 21.3 |
| random-add-remove | 100,000 | 4.870e+06 ns | 24.4 |
| random-add-remove | 1,000,000 | 1.773e+08 ns | 88.7 |

(`ns/op` divides by 2×entities, since each timed call is one add + one remove per entity.)

### Mixed frame/phase (`Loop.step`)

A composite pass combining movement-style writes (`Position += Velocity` via `iter2`),
health-style reads (`iter1`, no write), spawn/despawn churn, random access, and structural churn
(toggle a marker component), all in one `Loop.step`. Isolated single-phase variants use separate
worlds and **do not sum exactly** to the composite — this measures interaction/contention effects
too, not just each phase's standalone cost.

| Workload | Entities | Cycles | time/run |
|---|---:|---:|---:|
| full (all 5 phases) | 10,000 | 100 | 4.630e+07 ns |
| full (all 5 phases) | 100,000 | 20 | 9.271e+07 ns |
| movement-only | 10,000 | 100 | 3.968e+07 ns |
| health-read-only | 10,000 | 100 | 4.299e+06 ns |
| spawn-despawn-only | 10,000 | 100 | 2.198e+06 ns |
| random-access-only | 10,000 | 100 | 2.121e+05 ns |
| structural-churn-only | 10,000 | 100 | 3.838e+05 ns |

At 10,000 entities, movement dominates the composite (86% of the full-frame cost) — each movement
tick does a full `iter2` pass plus a `set_component` write per matched entity, while the churn/access
phases only touch a 1%-of-population batch per tick. The five isolated phases sum to ~4.68e+07 ns,
about 1% above the measured composite (4.63e+07 ns) — close at this scale, with the small gap being
the isolated-worlds caveat above (no guarantee the sign or size of that gap holds at other scales).

### Diagnostic: heavy compute

Skipped — SkyECS excludes this from its own win counts/ranking since it isn't ECS-specific, and the
same reasoning applies here.

## Methodology

### Not a cross-library comparison

This suite adapts [SkyECS's benchmark methodology and workload
taxonomy](https://github.com/jz315/SkyECS/blob/main/benches/BENCHMARKS.md), not its actual numbers —
no other OCaml ECS exists to compare against, and bridging into Rust/C via FFI to get "comparable"
figures would mix runtimes, GCs, and compilers in a way that's more misleading than informative (the
scope SkyECS's own README is careful to stay out of: "does not make claims about scheduling,
parallelism, or memory use"). What's genuinely portable is the *shape* of the workloads.

### Sparse-set vs. archetype: the fragmentation category is absent, not reinterpreted

SkyECS (like Bevy, Flecs, Shipyard) is archetype/table-based; `eon_ecs` is sparse-set per component,
with no archetypes at all. SkyECS's "random-fragmentation workloads" section specifically measures
archetype-table churn and fragmentation — there is no table to fragment in a sparse-set design, so
this entire category does not port to `eon_ecs`, and isn't reinterpreted into something else. In its
place, this suite adds a workload with no SkyECS equivalent: the **sparse-set adversarial worst
case** above, which is sparse-set storage's own honest worst case (a multi-component query whose
smallest involved set is still absolutely large, but rejects nearly everything it scans) — included
even though the numbers are unflattering, on purpose, for the same reason SkyECS includes its own
fragmentation matrix despite it being archetype storage's Achilles' heel.

### Deterministic benchmark inputs

Every distribution, permutation, and shuffle used above is either a pure deterministic function of
`(entity id, component index)` or an explicitly-seeded `Random.State`, computed before the timed
portion of each test. Nothing here depends on wall-clock time, unseeded `Random`, or accumulated
runtime history — a rerun on the same machine should reproduce the same numbers within normal
measurement noise.

### A note on how these numbers were produced

An earlier draft of this benchmark suite had a real bug: several `Test.make (Staged.stage (fun () ->
setup; fun () -> workload))` benchmarks returned an inner closure that Bechamel's `Staged.stage` (a
no-op identity in this library, not a "setup once, time repeatedly" mechanism) never actually calls —
silently measuring only the setup cost, not the labeled operation, for entire pre-existing suites in
`bench_world.ml`, `bench_query.ml`, and `bench_loop.ml`, plus three new `bench_entity_manager.ml`
workloads written the same way by mistake. All were rewritten to use `Test.make_with_resource`
(Bechamel's actual per-test allocate/free API — `Test.uniq` for read-only/idempotent workloads,
`Test.multiple` for one-shot "consuming" workloads like a single destroy-everything pass) before any
number in this file was recorded. The numbers above are the corrected results.

## Running these benchmarks

```sh
just bench sparse_set
just bench entity_manager
just bench query          # entity_count <= 10_000
just bench query_large    # entity_count > 10_000 (~110s; see bench_query_large.ml)
just bench world
just bench loop
just bench-ci              # full matrix, all of the above plus eon_engine/eon_edn benches
```

`bench_query.ml` and `bench_query_large.ml` share their builders and distribution cases via
`query_bench_defs.ml` — extend that file when adding new query workload shapes rather than
duplicating a builder into both executables.

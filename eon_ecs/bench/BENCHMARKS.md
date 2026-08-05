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

`time/run` is the duration of one timed call, as reported by Bechamel's OLS analysis
(`Benchmark_helpers.analyze_single_instance`/`pp_results`) and auto-scaled to the most readable unit
(ns/µs/ms/s — `format_duration_ns` picks the unit so the number stays in a 1–999 range rather than
requiring exponent notation). Every workload below with a `cycles`, `~` batch, or explicit op count
folded into the timing is called out per-row. The derived `ns/entity`/`ns/op` columns stay in plain
nanoseconds throughout, since those are already small, comparable numbers.

## Workload table

Grouped by the SkyECS-derived taxonomy from `ecs-047`'s task note. One representative distribution
("default") is shown per size for the general iteration/access workloads; the deliberately-scoped
fragmented/adversarial workloads are shown in full.

### Bulk / single insert

`eon_ecs` has one entity-creation path (`create_entity` + `add_component` per component, no batch
API) — bulk and single insert collapse into one shape; `component_count = 1` is "single insert."

| Workload | Entities | Components | time/run | ns/entity |
|---|---:|---:|---:|---:|
| bulk-insert | 10,000 | 1 | 463.8 µs | 46.4 |
| bulk-insert | 10,000 | 4 | 2.20 ms | 220.3 |
| bulk-insert | 100,000 | 4 | 20.97 ms | 209.7 |
| bulk-insert | 1,000,000 | 4 | 235.9 ms | 235.9 |

Scales linearly with entity count, as expected — no batch API means no amortization to lose.

### Prepared iteration (`Query.iter1`–`iter4`, `iter_entities`)

World population happens once per test (outside the timed portion — see
[Methodology](#methodology)); only the query call itself is timed. "default" distribution:
`eid mod (idx + 2) = 0` (component `idx` present on roughly `1/(idx+2)` of entities).

| Workload | Entities | Components | time/run |
|---|---:|---:|---:|
| iter1 | 10,000 | 1 | 23.13 µs |
| iter1 | 10,000 | 4 | 21.38 µs |
| iter1 | 50,000 | 4 | 106.10 µs |
| iter1 | 100,000 | 4 | 212.30 µs |
| iter1 | 1,000,000 | 4 | 2.12 ms |
| iter2 | 10,000 | 2 | 31.85 µs |
| iter2 | 10,000 | 4 | 32.64 µs |
| iter2 | 50,000 | 4 | 155.80 µs |
| iter2 | 100,000 | 4 | 301.30 µs |
| iter2 | 1,000,000 | 4 | 3.27 ms |
| iter3 | 10,000 | 3 | 28.79 µs |
| iter3 | 10,000 | 4 | 29.05 µs |
| iter3 | 50,000 | 4 | 143.00 µs |
| iter3 | 100,000 | 4 | 287.70 µs |
| iter3 | 1,000,000 | 4 | 3.20 ms |
| iter4 | 10,000 | 4 | 17.23 µs |
| iter4 | 10,000 | 6 | 17.24 µs |
| iter4 | 50,000 | 6 | 85.30 µs |
| iter4 | 100,000 | 6 | 173.30 µs |
| iter4 | 1,000,000 | 6 | 2.73 ms |
| iter_entities | 10,000 | 1 | 23.63 µs |
| iter_entities | 10,000 | 4 | 20.50 µs |
| iter_entities | 50,000 | 4 | 99.83 µs |
| iter_entities | 100,000 | 4 | 201.90 µs |
| iter_entities | 1,000,000 | 4 | 2.25 ms |

Distribution shape matters more than arity at a fixed size: `iter2` at 10,000 entities/4 components
ranges from 25.81 µs (`every-5`, sparse) to 131.50 µs (`all`, every entity matches) across the
suite's 7 distribution cases — a ~5x spread from density alone, before touching size or arity. The
full per-distribution breakdown is in the raw `just bench query`/`query_large` output, not reproduced
here in full.

### Fragmented iteration

Each component in the signature draws membership independently at a low, shared probability (5% or
1%) — a multi-component query's match count shrinks geometrically with arity even though no single
component's sparse set is tiny. Less extreme than the dedicated adversarial worst case below.

| Workload | Entities | Distribution | time/run |
|---|---:|---|---:|
| iter2-fragmented | 100,000 | p=5% | 49.81 µs |
| iter2-fragmented | 100,000 | p=1% | 5.77 µs |
| iter2-fragmented | 1,000,000 | p=5% | 387.20 µs |
| iter2-fragmented | 1,000,000 | p=1% | 95.72 µs |
| iter3-fragmented | 100,000 | p=5% | 36.07 µs |
| iter3-fragmented | 100,000 | p=1% | 5.94 µs |
| iter3-fragmented | 1,000,000 | p=5% | 380.30 µs |
| iter3-fragmented | 1,000,000 | p=1% | 120.50 µs |

### Sparse-set adversarial worst case

Not in SkyECS — added deliberately (see [Methodology](#methodology)). Two/three components each
present on ~0.1% of the world, drawn independently so their intersection is close to empty. The
smallest involved sparse set is hundreds to low thousands of entities in absolute terms, but the scan
rejects almost every candidate it walks. **This is the baseline `ecs-050`'s `Cached_backend` is
measured against.**

| Workload | Entities | time/run |
|---|---:|---:|
| iter2-adversarial | 100,000 | 606.5 ns |
| iter2-adversarial | 1,000,000 | 9.84 µs |
| iter3-adversarial | 100,000 | 759.7 ns |
| iter3-adversarial | 1,000,000 | 7.19 µs |

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
| hit | 1,000 | 10 | 181.70 µs | 18.2 |
| hit | 10,000 | 5 | 904.60 µs | 18.1 |
| hit | 100,000 | 2 | 3.63 ms | 18.2 |
| hit | 1,000,000 | 1 | 18.29 ms | 18.3 |
| mixed | 1,000 | 10 | 178.00 µs | 17.8 |
| mixed | 10,000 | 5 | 906.70 µs | 18.1 |
| mixed | 100,000 | 2 | 3.77 ms | 18.9 |
| mixed | 1,000,000 | 1 | 17.94 ms | 17.9 |
| random50 | 1,000 | 10 | 228.20 µs | 22.8 |
| random50 | 10,000 | 5 | 1.17 ms | 23.3 |
| random50 | 100,000 | 2 | 4.61 ms | 23.1 |
| random50 | 1,000,000 | 1 | 22.56 ms | 22.6 |
| clustered | 1,000 | 10 | 178.30 µs | 17.8 |
| clustered | 10,000 | 5 | 895.10 µs | 17.9 |
| clustered | 100,000 | 2 | 3.58 ms | 17.9 |
| clustered | 1,000,000 | 1 | 18.24 ms | 18.2 |

`random50`'s ~25% higher per-op cost than the other three is consistent across every size — the
uniformly-random present/absent pattern defeats branch prediction/prefetching in a way the
contiguous `clustered` split (same 50% rate) doesn't.

### Spawn / random despawn

Entities and a full deterministic destroy-order shuffle are prepared once per timed call (outside
timing); only the destroy pass itself is measured.

| Workload | Entities | time/run | ns/entity |
|---|---:|---:|---:|
| despawn-only | 10,000 | 201.20 µs | 20.1 |
| despawn-only | 100,000 | 2.17 ms | 21.7 |
| despawn-only | 1,000,000 | 35.63 ms | 35.6 |

### Random add/remove component churn

Two independent deterministic permutations (insert order, removal order); the timed call is one
full add-pass followed by one full remove-pass.

| Workload | Entities | time/run | ns/op |
|---|---:|---:|---:|
| random-add-remove | 10,000 | 426.70 µs | 21.3 |
| random-add-remove | 100,000 | 4.87 ms | 24.4 |
| random-add-remove | 1,000,000 | 177.30 ms | 88.7 |

(`ns/op` divides by 2×entities, since each timed call is one add + one remove per entity.)

### Mixed frame/phase (`Loop.step`)

A composite pass combining movement-style writes (`Position += Velocity` via `iter2`),
health-style reads (`iter1`, no write), spawn/despawn churn, random access, and structural churn
(toggle a marker component), all in one `Loop.step`. Isolated single-phase variants use separate
worlds and **do not sum exactly** to the composite — this measures interaction/contention effects
too, not just each phase's standalone cost.

| Workload | Entities | Cycles | time/run |
|---|---:|---:|---:|
| full (all 5 phases) | 10,000 | 100 | 46.30 ms |
| full (all 5 phases) | 100,000 | 20 | 92.71 ms |
| movement-only | 10,000 | 100 | 39.68 ms |
| health-read-only | 10,000 | 100 | 4.30 ms |
| spawn-despawn-only | 10,000 | 100 | 2.20 ms |
| random-access-only | 10,000 | 100 | 212.10 µs |
| structural-churn-only | 10,000 | 100 | 383.80 µs |

At 10,000 entities, movement dominates the composite (86% of the full-frame cost) — each movement
tick does a full `iter2` pass plus a `set_component` write per matched entity, while the churn/access
phases only touch a 1%-of-population batch per tick. The five isolated phases sum to ~46.80 ms,
about 1% above the measured composite (46.30 ms) — close at this scale, with the small gap being
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

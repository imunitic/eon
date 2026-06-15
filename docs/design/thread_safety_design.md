# Thread Safety & Parallel Pipeline Design

## Status

**DRAFT — not finished.** Proposed / design notes. Captures the concurrency philosophy and the
engine-layer parallel pipeline model. Interacts with
[world_module_design.md](world_module_design.md) and
[query_view_design.md](query_view_design.md) (read access via the view).

---

## 1. Philosophy

**eon_ecs and eon_engine are single-threaded by default and never impose a
thread-safety solution.** Concurrency correctness is the **user's**
responsibility — the user knows their game's shared-data access patterns, so
they write the correct concurrent code. The libraries' job is only to make it
*possible* to add thread-safe solutions, guaranteed through documented design
choices and extension seams — not to ship locks, atomics, or a scheduler the
user didn't ask for.

This is the concurrency expression of the lean-essential-core stance: the core
stays simple and opinionated; anything heavier is opt-in. (Contrast Bevy / Unity
DOTS, which auto-parallelize and impose a scheduler.)

When concurrency comes up, the answer is a **seam** — a phase tag, a functor
parameter, a typed world view, a documented invariant — never an imposed
solution baked into the core.

---

## 2. Layering: opinionated sequential core, opt-in parallel engine

- **`eon_ecs` is strictly sequential and opinionated.** Pipelines and systems run
  sequentially, full stop. No parallelism, no locks, no atomics-for-safety in the
  core. This opinion is a *feature*: it gives the engine well-defined barriers to
  build on. If the core left phase ordering loose, the engine could not promise
  the barriers the parallel model depends on.
- **`eon_engine` ships its own pipeline** with sequential *phases* but optionally
  *parallel systems within a phase*, gated by `Read_only` / `Read_write` phase
  tags. This is opt-in and layered on top of the sequential core.

```
game code
    ↓
Engine parallel pipeline   ← Read_only/Read_write phase tags, parallel systems (eon_engine)
    ↓
Sequential primitives      ← Pipeline/System, strictly sequential (eon_ecs, unchanged)
```

---

## 3. The sequential-phase invariant (the backbone)

**Phases are always sequential.** This is load-bearing: each phase boundary is a
guaranteed sync point. Everything below — the index rebuild, the bus merge, the
dirty-flag settling — anchors to phase boundaries. The *only* concurrency is
*within* a phase, among its systems.

```
Phases: strictly sequential  → they ARE the barriers
Systems within a Read_only phase: parallel → the only concurrency
```

If phases could overlap there would be no well-defined moment where "all writes
are done and reads may begin," and none of the mechanisms below would have an
anchor. The read/write phase separation is only meaningful because a write phase
cannot run concurrently with a read phase.

---

## 4. Phase tags: `Read_only` / `Read_write`

- A **`Read_only`** phase's systems only read world state → they may be run in
  parallel (multiple readers, no writer).
- A **`Read_write`** phase's systems may mutate → they run sequentially.
- Phases themselves always run sequentially regardless of tag.

### The unchecked invariant

In OCaml there is no borrow checker. A system in a `Read_only` phase *can* still
call `World.set_component` — the compiler will not stop it by default. So the
safety of parallelizing a `Read_only` phase rests on the user **honestly
tagging** (and honestly keeping `update` write-free). The parallel runner
*trusts* the tag; it cannot verify it. This is consistent with "concurrency is
the user's responsibility," but it must be documented as the load-bearing
invariant, not buried.

§7 describes an optional way to turn this promise into a compile-time guarantee.

---

## 5. Frame order and where parallelism sits

From [loop.ml](../../eon_ecs/loop.ml), each frame is:

```
Buses.collect   →   Progress.tick   →   Buses.drain   →   Renderer.render
```

- **`Progress.tick`** runs system `update` functions → the **read phase**
  (queries). This is where parallel `Read_only` systems run.
- **`Buses.collect`** (frame start) and **`Buses.drain`** (frame end) are where
  `on_*` handlers fire → the **write phase**. Both sit *outside* `tick`.

A well-structured reactive Eon game keeps this split clean: **`update` only
reads; `on_*` handlers only write.** Given that discipline, reads and writes
never interleave within a frame, and the parallel read phase has no active
writer.

---

## 6. Query iteration under parallelism

The current backend is sparse-set based (`iter1`/`iter2`/`iter3`/`iter4` in
`Eon_ecs.Query`). There is **no index to rebuild** — queries walk sparse sets
directly, with `iter2`–`iter4` picking the smallest set as the iteration base
and checking membership in the others. This is inherently stateless on the read
path.

The parallelism concern is therefore **structural mutation**, not index
reconstruction. `add_component`, `remove_component`, and `destroy_entity` all
mutate sparse sets — inserting or removing entries in the dense array and index
table. If a `Read_only` phase runs such mutations concurrently with queries, the
iterating worker races with the mutating one even though the system is tagged
read-only.

**Resolution — confine structural mutations to the write side of the frame
boundary.** A structurally safe `Read_only` phase requires that no `add_`,
`remove_`, or `destroy_` calls are in flight during `Progress.tick`. Given the
frame order:

```
Buses.collect  →  Progress.tick  →  Buses.drain  →  Renderer.render
```

structural mutations come from `on_*` handlers, which fire during `collect` and
`drain` — both outside `tick`. As long as the §5 discipline holds (update only
reads; on_* handlers only write), the parallel read phase sees a structurally
frozen world with no active writers.

No boundary sync step is needed beyond what the frame order already provides.
Layering: the engine's parallel loop enforces the phase boundary; `eon_ecs` core
needs nothing.

---

## 7. Optional enforcement: typed `RO` / `RW` world views

The §4 invariant can be promoted from a documented promise to a **compile-time
guarantee** using **phantom capability types** — OCaml's idiom for read/write
capabilities, essentially a hand-rolled `&World` vs `&mut World`.

### Shape

```ocaml
type 'perm t   (* phantom — 'perm has no runtime representation *)

val get_component : [> `R ] t -> ...    (* readers need at least R *)
val set_component : [> `W ] t -> ...    (* writers need W          *)
```

- Read-only world: `[ `R ] t`. Read-write: `[ `R | `W ] t`.
- `get` accepts both; `set` accepts only `[ `R | `W ]` — calling it on a
  `[ `R ] t` fails to typecheck (no `W` tag).
- `update : [ `R ] t -> dt -> unit`; `on_command : [ `R | `W ] t -> ... -> unit`.
- Mark the phantom **contravariant** (`type -'perm t`) so a read-write world
  coerces down to read-only where `update` expects it.

A simpler first cut (while ramping on OCaml): two abstract types `ro` / `rw` with
a one-way `readonly : rw -> ro` downgrade and separate read/write function sets.
Less elegant, trivial to reason about, upgradeable to the phantom encoding later.

### Where it lives — engine layer, not core

Do **not** phantom-type the core `Eon_ecs.World.t`: adding `'perm` is not
additive, it changes an existing public type and ripples the parameter through
`Query`, `System`, `Loop`. Instead, the engine wraps the raw world:

```ocaml
type 'perm t = { raw : Eon_ecs.World.t }   (* phantom 'perm; core stays unparametrized *)
```

and exposes capability-constrained read/write ops delegating to the plain core.
Core stays simple and unparametrized; capability typing lives where the parallel
pipeline does.

### Limits (what "enforced" means)

1. **Guards the world API, not mutation reachable through it.** If `update`
   fetches a service/resource (service plane) whose value is mutable (`ref`,
   `Hashtbl`, `Atomic`), it can mutate *through* it; the phantom cannot see that.
   So `RO` proves "no component/entity mutation via the world API," not "no side
   effects." **Rust has the same escape hatch** (`Res<Mutex<T>>` interior
   mutability) — it lands cleanly on the philosophy: enforced for the direct
   path, user's responsibility beyond it.
2. **Closures can launder capabilities** — a handler could capture an `rw` world
   and stash it where an `update` later reaches it. Rare, but untracked by the
   phantom.

### `WO` (write-only) handlers?

Expressible, but usually impractical — handlers typically read current state to
decide what to write. `RW` for handlers is the pragmatic default; reserve `WO`
for the rare blind-write handler.

---

## 8. Buses under parallelism

Signals / Events / Commands are emitted-to during systems. If parallel systems
`emit` to one shared bus concurrently, that races — unless the bus is
thread-safe, which would violate "no thread-safety imposed in core."

**Model (Bevy-style): parallelize only the `emit`; keep dispatch sequential.**

- Each worker gets a **thread-local buffer**; `emit` appends to it. Appends to
  per-worker buffers do not race.
- Handlers / subscriber callbacks (which may mutate the world) are **never** run
  concurrently — they fire sequentially at the sync point, exactly as today.
- Merge the per-worker buffers at the **phase barrier** (the end-of-parallel-phase
  sync point), before any subsequent phase or drain reads them. Deferring all the
  way to "just before drain" is correct only if no intervening same-tick phase
  inspects the bus; merging at the barrier is the safer general rule.

Per bus:

| Bus | Type | Merge target |
|---|---|---|
| Signals | `Single_bus` | merge into main queue at barrier; handlers fire at drain |
| Commands | `Single_bus` | merge into main queue at barrier; handlers fire at drain |
| Events | `Double_bus` | merge into the `next` queue before the end-of-frame swap |

**The merge must be deterministic** — stable worker order (e.g. worker index,
then local append order). Otherwise command/event ordering varies run-to-run and
you lose reproducibility (replays, deterministic netcode, debugging). Parallel
*execution*, deterministic *merge*.

> Status: a fully worked parallel-bus design is **not yet settled** — this is the
> agreed model/direction, not a final spec.

---

## 9. Invariants Summary

The parallel read phase is safe **iff** all of these hold:

1. **Phases run sequentially** (§3) — the barriers exist.
2. **`Read_only` phases contain no writers** (§4) — by tag honesty, or enforced
   by `RO` world views (§7).
3. **No structural mutations (`add_component`, `remove_component`,
   `destroy_entity`) are in flight during `tick`** — they are confined to
   `on_*` handlers in `collect`/`drain`, outside the parallel phase (§6).
4. **Bus `emit` is per-worker-buffered; dispatch stays sequential; merge is
   deterministic at the phase barrier** (§8).

In OCaml, (2) is a promise unless §7 is adopted; (1), (3), (4) are structural
guarantees the engine pipeline provides.

---

## 10. What NOT to Do

- **Do not add locks/atomics/thread-safe structures to `eon_ecs` core "for
  safety."** Concurrency is a seam, not an imposed core feature.
- **Do not run subscriber/handler callbacks concurrently.** Only `emit`
  (buffer append) and `Read_only` system `update` run in parallel; everything
  that can mutate stays sequential at a barrier.
- **Do not call `add_component`, `remove_component`, or `destroy_entity` inside a
  `Read_only` phase's `update`.** Structural mutations must stay in `on_*`
  handlers that fire during `collect`/`drain`, never during the parallel `tick`.
- **Do not phantom-type the core `World.t`.** If `RO`/`RW` views are adopted,
  they live in `eon_engine` over `world.raw`.
- **Do not assume a non-deterministic merge is acceptable.** Determinism is a
  requirement, not a nice-to-have.

---

## 11. Pipeline Implementation (decided)

The engine ships its own **`Eon_engine.Pipeline.Make(System)(Executor)`**
functor — the same Make idiom as the core's `Pipeline.Make`, **not** a wrapper
over the core pipeline, and entirely engine-side (`eon_ecs` untouched).

- **The dependency graph is extracted into the core as a public primitive.**
  Today the core's `topo_sort` lives *inside* its `Make` functor body
  ([pipeline.ml:112](../../eon_ecs/pipeline.ml)), so it is not callable without
  instantiating the core functor, and the engine package — being separate — could
  not reuse it at all without duplicating ~35 lines. Instead of duplicating, we
  pull the dependency-ordering logic out into its own module,
  `Eon_ecs.Dependency_graph` (a generic DAG: add node, add `before`/`after`
  edge, `topo_sort`, cycle detection), and **re-export it from `eon_ecs.mli`** so
  the engine package can depend on it. `Eon_ecs.Pipeline.Make` is refactored to
  *delegate* to it (behaviour-preserving — same ordering, same cache-invalidation
  semantics), and `Eon_engine.Pipeline.Make(System)(Executor)` reuses the same
  primitive rather than re-implementing the graph.

  *Why this is an `eon_ecs` change worth making:* topo-sort is not a
  *responsibility* of the pipeline — it is a *dependency* the pipeline consumes.
  The pipeline's job is phase scheduling and system execution; ordering a DAG is
  a separable, fundamental, stable concern. Extracting it is a separation-of-
  concerns refactor that also yields a reusable public seam (users building their
  own schedulers get it too). It clears the same bar as `iter_entities`:
  fundamental, philosophy-preserving, additive (new public module, no signature
  change to existing API), and now backed by **two concrete consumers** (both
  pipelines). The trade-off is added public surface + a behaviour-preserving
  refactor of `Pipeline.Make` versus the ~35-line duplicate — and the package
  boundary makes duplication the *only* alternative, since a functor-body-local
  helper cannot cross into `eon_engine`.

  Only the execution loop is necessarily reimplemented in the engine variant,
  since it goes from a sequential fold to tag-aware dispatch — that genuinely is
  pipeline-specific and stays per-pipeline.
- **Phase tags ride the existing metadata slot.** The core stores phases as
  `('phase, unit) Hashtbl.t` — that `unit` is a placeholder. The engine variant
  stores `('phase, phase_kind)` carrying `Read_only` / `Read_write`.
- **Execution:** `Read_write` phases run their systems sequentially; `Read_only`
  phases dispatch systems through `Executor`. A `Sequential` executor recovers
  exactly the core's behaviour, so the parallel pipeline degrades cleanly.
- **Orthogonality:** the phase tag is independent of the existing system `kind`
  (`run_by_filter`, used for fixed/variable timestep filtering). Do not conflate
  them.

## 12. Open Decisions

1. **Ship `RO`/`RW` world views?** Phantom-capability enforcement (§7) is a real
   upgrade but adds API surface; decide whether it's in-scope for the first
   parallel pipeline or a later hardening pass.
2. **Concrete executor(s).** The `Executor` functor parameter (§11) is the
   threading-substrate seam: ship `Sequential` (default, core-equivalent) plus at
   least one parallel executor. Which first — Domains (OCaml 5), a thread pool? —
   and is a user-supplied executor a documented extension point from day one?
3. **Parallel-bus spec.** Finalize per-worker buffer ownership, the merge API,
   and the deterministic ordering rule (§8).

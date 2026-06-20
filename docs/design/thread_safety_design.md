# Thread Safety & Parallel Pipeline Design

## Status

**DRAFT — not finished.** Proposed / design notes. Captures the concurrency philosophy and the
engine-layer parallel pipeline model. Interacts with
[world_module_design.md](world_module_design.md) and
[query_view_design.md](query_view_design.md) (read access via the view).

The concrete implementation specification — module shapes, functor signatures,
`Executor.S` interface, and bus merge protocol — lives in
[parallel_pipeline_execution.md](parallel_pipeline_execution.md). This document
is the philosophy and invariants; that document is the how.

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
guaranteed sync point. Everything below — the bus merge, the dirty-flag settling
— anchors to phase boundaries. The *only* concurrency is *within* a phase,
among its systems' `update` calls.

```
Phases: strictly sequential  → they ARE the barriers
System updates within a phase: parallel → the only concurrency
```

---

## 4. No phase tags — `World_cap` does the job

Earlier designs proposed `Read_only` / `Read_write` phase tags to distinguish
parallel-safe from parallel-unsafe phases. **These are dropped.**

The parallel pipeline only accepts **reactive systems**, whose `update` always
takes `World_cap.ro World_cap.t`. Since all updates are read-only by the type
system, every phase's updates are safe to run in parallel — no per-phase tag
is needed to make that determination. `World_cap` enforces the invariant at
compile time; a phase tag would only document a promise the compiler already
checks.

```
update    : World_cap.ro World_cap.t → float → unit   (* all phases, parallel *)
on_signal : World_cap.rw World_cap.t → 's → unit      (* always sequential *)
on_event  : World_cap.rw World_cap.t → 'e → unit      (* always sequential *)
on_command: World_cap.rw World_cap.t → 'c → unit      (* always sequential *)
```

Phases still exist for **ordering** — controlling which groups of systems run
before others. That job is independent of parallel/sequential dispatch.

---

## 5. Frame order and where parallelism sits

From [loop.ml](../../eon_ecs/loop.ml), each frame is:

```
Buses.collect   →   Progress.tick   →   Buses.drain   →   Renderer.render
```

- **`Progress.tick`** runs system `update` functions → all parallel, all `ro`.
- **`Buses.collect`** (frame start) and **`Buses.drain`** (frame end) are where
  `on_*` handlers fire → always sequential, always `rw`. Both sit *outside* `tick`.

The frame order enforces the split structurally: reads and writes never
interleave within a frame, and the parallel `tick` window has no active writer.

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

## 7. Enforcement: typed `RO` / `RW` world views

**Decided: ship with the first parallel pipeline.**

The §4 invariant is promoted from a documented promise to a **compile-time
guarantee** using **phantom capability types** — OCaml's idiom for read/write
capabilities, essentially a hand-rolled `&World` vs `&mut World`.

### Optional — parallel pipeline only

`World_cap` is only used when the parallel pipeline is used. The two stacks
are fully independent:

| Stack | World type | When to use |
|---|---|---|
| Sequential | `Eon_engine.World.t` | `Eon_ecs.Pipeline` or sequential `Eon_engine.Pipeline` |
| Parallel | `World_cap.ro/rw World_cap.t` | `Eon_engine.Pipeline` (parallel) |

A game that never needs parallelism never sees `World_cap`. The parallel
pipeline is the only code that calls `World_cap.wrap` and `World_cap.readonly`.

### Shape — Option A (decided)

`ro` and `rw` are type aliases for polymorphic variants. This keeps the API
readable while making a future upgrade to full phantom contravariance (Option B)
a one-line change with zero call-site impact:

```ocaml
type ro = [ `R ]
type rw = [ `R | `W ]
```

- `update : ro World_cap.t -> float -> unit` — systems only read.
- `on_command : rw World_cap.t -> ... -> unit` — handlers may write.

### Option B (deferred — upgrade path)

Full phantom contravariance — mark `type -'perm t` and use `[> `R ]` /
`[> `R | `W ]` constraints directly. `rw t` coerces to `ro t` automatically,
no explicit `readonly` call needed. Because `ro` and `rw` are already aliases
for the variant types, switching is a one-line change; call sites are unaffected.

### Full `World_cap` interface

```ocaml
(* eon_engine/world_cap.mli *)

(* ================================================================ *)
(* Capability types                                                   *)
(* ================================================================ *)

type ro = [ `R ]
type rw = [ `R | `W ]

(* ================================================================ *)
(* Capability-wrapped world                                           *)
(* ================================================================ *)

type 'perm t  (* phantom — 'perm has no runtime representation *)

(* ================================================================ *)
(* Construction — parallel pipeline internal; game code never calls  *)
(* ================================================================ *)

val wrap     : World.t -> rw t   (* pipeline wraps before dispatch *)
val readonly : rw t -> ro t      (* pipeline calls before Read_only phase *)

(* ================================================================ *)
(* Read operations — both perms                                       *)
(* ================================================================ *)

val get_component         : _ t -> Entity_id.t -> 'a Component_descriptor.t -> 'a option
val is_alive              : _ t -> Entity_id.t -> bool
val count_entities        : _ t -> int
val is_registered         : _ t -> 'a Component_descriptor.t -> bool
val get_data              : _ t -> [> ] -> 'a option
val get_service           : _ t -> [> ] -> 'a option
val list_services         : _ t -> int list
val iter_entities         : _ t -> string list -> (Entity_id.t -> unit) -> unit
val has_component         : _ t -> Entity_id.t -> string -> bool

(* ================================================================ *)
(* Write operations — rw only                                         *)
(* ================================================================ *)

val create_entity         : rw t -> Entity_id.t
val destroy_entity        : rw t -> Entity_id.t -> unit
val add_component         : rw t -> Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
val set_component         : rw t -> Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
val remove_component      : rw t -> Entity_id.t -> 'a Component_descriptor.t -> unit
val remove_all_components : rw t -> Entity_id.t -> unit
val register              : rw t -> 'a Component_descriptor.t -> Component_descriptor.registration_result
val add_data              : rw t -> [> ] -> 'a -> unit
val set_data              : rw t -> [> ] -> 'a -> unit
val add_service           : rw t -> [> ] -> 'a -> unit
```

The implementation is pure delegation to `World` with zero runtime overhead:

```ocaml
(* eon_engine/world_cap.ml *)

type ro = [ `R ]
type rw = [ `R | `W ]

type 'perm t = { raw : World.t }

let wrap w     = { raw = w }
let readonly w = { raw = w.raw }

(* reads — accept any perm *)
let get_component w e c        = World.get_component w.raw e c
let is_alive w e               = World.is_alive w.raw e
let count_entities w           = World.count_entities w.raw
let is_registered w c          = World.is_registered w.raw c
let get_data w k               = World.get_data w.raw k
let get_service w k            = World.get_service w.raw k
let list_services w            = World.list_services w.raw
let iter_entities w names f    = World.iter_entities w.raw names f
let has_component w e name     = World.has_component w.raw e name

(* writes — rw only; type system rejects ro at call site *)
let create_entity w            = World.create_entity w.raw
let destroy_entity w e         = World.destroy_entity w.raw e
let add_component w e c v      = World.add_component w.raw e c v
let set_component w e c v      = World.set_component w.raw e c v
let remove_component w e c     = World.remove_component w.raw e c
let remove_all_components w e  = World.remove_all_components w.raw e
let register w c               = World.register w.raw c
let add_data w k v             = World.add_data w.raw k v
let set_data w k v             = World.set_data w.raw k v
let add_service w k v          = World.add_service w.raw k v
```

### Limits (what "enforced" means)

1. **Guards the world API, not mutation reachable through it.** If `update`
   fetches a service/resource whose value is mutable (`ref`, `Hashtbl`,
   `Atomic`), it can mutate *through* it; the phantom cannot see that. `RO`
   proves "no component/entity mutation via the world API," not "no side
   effects." Rust has the same escape hatch (`Res<Mutex<T>>` interior
   mutability) — enforced for the direct path, user's responsibility beyond it.
2. **Closures can launder capabilities** — a handler could capture an `rw`
   world and stash it where an `update` later reaches it. Rare, but untracked
   by the phantom.

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

The parallel `tick` is safe **iff** all of these hold:

1. **Phases run sequentially** (§3) — the barriers exist.
2. **All system `update` functions are read-only** (§4) — enforced at compile
   time by `World_cap.ro World_cap.t` (§7).
3. **No structural mutations (`add_component`, `remove_component`,
   `destroy_entity`) are in flight during `tick`** — they are confined to
   `on_*` handlers in `collect`/`drain`, outside the parallel window (§6).
4. **Bus `emit` is `Mutex`-protected; dispatch stays sequential** (§8).

Invariants (1), (3), and (4) are structural guarantees from the pipeline and
frame order. Invariant (2) is a compile-time guarantee enforced by `World_cap`.

---

## 10. What NOT to Do

- **Do not add locks/atomics/thread-safe structures to `eon_ecs` core "for
  safety."** Concurrency is a seam, not an imposed core feature.
- **Do not run subscriber/handler callbacks concurrently.** Only system
  `update` runs in parallel; everything that can mutate stays sequential at a
  barrier.
- **Do not call `add_component`, `remove_component`, or `destroy_entity` inside
  `update`.** Structural mutations must stay in `on_*` handlers that fire during
  `collect`/`drain`, never during the parallel `tick`. `World_cap.ro` enforces
  this at the type level.
- **Do not phantom-type the core `World.t`.** `World_cap` lives in `eon_engine`
  and wraps `World.t`; the core stays unparametrized.

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

1. **Ship `RO`/`RW` world views?** Decided: yes, with the first parallel
   pipeline. Option A (`ro`/`rw` aliases + explicit `readonly` downgrade) — see
   §7 for the full design.
2. **Concrete executor(s).** The `Executor` functor parameter (§11) is the
   threading-substrate seam: ship `Sequential` (default, core-equivalent) plus at
   least one parallel executor. Which first — Domains (OCaml 5), a thread pool? —
   and is a user-supplied executor a documented extension point from day one?
3. **Parallel-bus spec.** The per-worker buffer approach was rejected (cannot
   be contained in the Executor without touching World, bus, or system
   interface). The agreed fix is a `Mutex` on `emit` only. **Decided:**
   `eon_engine` owns its own `Single_bus` / `Double_bus` implementations with
   a mutex on `emit`; `eon_ecs` buses are left completely untouched. See
   [parallel_pipeline_execution.md §8](parallel_pipeline_execution.md).

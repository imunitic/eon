# Parallel Pipeline Execution — `eon_engine`

## Status

**DRAFT — active design.** Implementation specification for the `eon_engine`
parallel pipeline. The concurrency philosophy, invariants, and frame-order
constraints live in [thread_safety_design.md](thread_safety_design.md) — read
that first. This document translates those decisions into concrete module
shapes, functor signatures, and execution algorithms.

---

## 1. Scope and Relationship to Core

`eon_ecs` is strictly sequential and stays that way. The parallel pipeline is
entirely an `eon_engine` concern: a new `Eon_engine.Pipeline.Make(System)(Executor)`
functor that reuses the same `Make` idiom as the core pipeline but replaces the
sequential execution fold with tag-aware dispatch.

The only `eon_ecs` change required is extracting `topo_sort` into a public
`Eon_ecs.Dependency_graph` primitive so the engine pipeline can reuse it
without duplicating ~35 lines across a package boundary (§2 below).

```
eon_engine
  Eon_engine.System                            ← new; update : ro World_cap.t, on_* : rw World_cap.t
  Eon_engine.Pipeline.Make(System)(Executor)   ← new; all phases dispatched via Executor
  Eon_engine.Executor.Sequential               ← default; recovers sequential behaviour
  Eon_engine.Executor.Domain_pool              ← parallel; OCaml 5 Domains
  Eon_engine.World_cap                         ← phantom capability wrapper; pipeline-internal

eon_ecs (additive change only)
  Eon_ecs.Dependency_graph                     ← extracted topo-sort primitive (new public module)
  Eon_ecs.Pipeline.Make                        ← refactored to delegate to Dependency_graph
```

---

## 2. `Eon_ecs.Dependency_graph` — Extracted Topo-Sort Primitive

Today's `topo_sort` is a functor-body-local function in
`eon_ecs/pipeline.ml:112`. It cannot be called without instantiating the
core functor, and it cannot cross the package boundary into `eon_engine`
without duplication.

The fix: lift it into a standalone public module.

### 2.1 Interface

```ocaml
(** Generic directed-acyclic-graph with topological sort.
    ['node] must be comparable with structural equality. *)
module Dependency_graph : sig
  type 'node t

  val create   : unit -> 'node t
  val add_node : 'node -> 'node t -> 'node t
  (** [before ~earlier ~later g] records that [earlier] must precede [later]. *)
  val before   : earlier:'node -> later:'node -> 'node t -> 'node t

  (** Return nodes in topological order.
      Raises [Invalid_argument] if a cycle is detected. *)
  val topo_sort : 'node t -> 'node list

  (** True if no edges have been added since the last [topo_sort] call. *)
  val is_clean : 'node t -> bool
end
```

`topo_sort` caches its result and invalidates on `add_node` / `before` — the
same cache-invalidation semantics the pipeline currently has via
`order_cache`.

### 2.2 Impact on `Eon_ecs.Pipeline.Make`

`Pipeline.Make` is refactored to hold a `'phase Dependency_graph.t` in
place of the raw `edges` list and the `order_cache` field. The cache is
managed inside `Dependency_graph`. Externally observable behaviour is
unchanged.

---

## 3. No Phase Tags

Earlier designs proposed `Read_only` / `Read_write` phase tags to control
parallel vs sequential dispatch. **These are dropped.**

The parallel pipeline only accepts reactive systems whose `update` always takes
`World_cap.ro World_cap.t`. Since `World_cap` enforces read-only at compile
time, every phase's updates are safe to run in parallel — a per-phase tag
would only re-state what the type system already guarantees.

Phases still exist for **ordering** (which groups of systems run before others),
using the same `before`/`after` edges as the core pipeline. The phase table
stays `('phase, unit) Hashtbl.t` — no phase kind stored.

### 3.1 Orthogonality with System Kind

System kind (`Fixed`/`Variable`) governs *timestep scheduling* (`run_by_filter`
/ `Progress`) and is unaffected by this change.

---

## 4. `Executor.S` — The Threading-Substrate Seam

The `Executor` functor parameter is the only place where a threading library
touches the pipeline. All scheduling logic stays in the pipeline; the executor
only receives a list of jobs and runs them.

```ocaml
module type Executor = sig
  (** Run all [jobs] and block until every one completes.
      Jobs may run concurrently; the implementation decides how. *)
  val run_all : (unit -> unit) list -> unit
end
```

`run_all` is a synchronous call — it returns only after every job has
finished. This makes the phase barrier automatic: after `run_all` returns,
the next phase begins.

### 4.1 `Sequential` (default)

```ocaml
module Sequential : Executor = struct
  let run_all jobs = List.iter (fun f -> f ()) jobs
end
```

Degrades the parallel pipeline to exactly the core's sequential behaviour.
Use this as the default and for testing.

### 4.2 `Domain_pool` (parallel, OCaml 5)

A pool of `n` OCaml 5 `Domain`s that dequeues and runs jobs concurrently.
`run_all` blocks (e.g. via `Mutex`/`Condition` or `Domain.join`) until the
queue is empty and all workers are idle.

The concrete implementation is intentionally deferred (open decision §9.2).
The executor module boundary is what matters: it is the only place a Domain
or thread ever appears in the pipeline code.

---

## 5. `Eon_engine.System`

The only public system type for the parallel pipeline. `update` is the sole
mandatory argument; all `on_*` handlers are optional and default to no-ops.

```ocaml
(* eon_engine/system.mli *)

type kind = [ `Fixed | `Variable ]

type ('s, 'e, 'c) t = {
  update     : World_cap.ro World_cap.t -> float -> unit;
  on_signal  : World_cap.rw World_cap.t -> 's -> unit;
  on_event   : World_cap.rw World_cap.t -> 'e -> unit;
  on_command : World_cap.rw World_cap.t -> 'c -> unit;
  kind       : kind;
}

val make :
  ?on_signal:(World_cap.rw World_cap.t -> 's -> unit) ->
  ?on_event:(World_cap.rw World_cap.t -> 'e -> unit) ->
  ?on_command:(World_cap.rw World_cap.t -> 'c -> unit) ->
  ?kind:kind ->
  (World_cap.ro World_cap.t -> float -> unit) ->
  ('s, 'e, 'c) t
```

`kind` defaults to `` `Variable ``. The `on_*` defaults are no-ops
(`fun _ _ -> ()`), leaving `'s`, `'e`, `'c` unconstrained for non-reactive
systems. Bus types constrain them at registration if handlers are provided.

**Non-reactive system** — reads world state, optionally emits, no handlers:
```ocaml
System.make (fun world dt ->
  Query.iter world [ Position.name; Velocity.name ] (fun view ->
    let vel = View.get view Velocity.component in
    Bus.emit commands (Move (entity, vel))))
```

**Reactive system** — reads in update, writes in handlers:
```ocaml
System.make
  ~on_command:(fun world cmd -> match cmd with
    | Move (e, vel) -> World_cap.set_component world e Velocity.component vel
    | _ -> ())
  (fun world dt ->
    (* read-only queries here *))
```

This is the only system type the parallel pipeline accepts. `Eon_ecs.System`
is incompatible by design — the parallel pipeline requires `World_cap` types.

---

## 6. `Eon_engine.Pipeline.Make` — Functor Signature

> Takes `System : System.S` where `System.S` is the `Eon_engine.System`
> signature above.

```ocaml
module Make
    (System   : System.S)
    (Executor : Executor)
  : sig
  type 'phase t

  val create     : unit -> 'phase t
  val add_phase  : 'phase -> 'phase t -> 'phase t
  val before     : earlier:'phase -> later:'phase -> 'phase t -> 'phase t
  val after      : later:'phase  -> earlier:'phase -> 'phase t -> 'phase t
  val add_system : 'phase -> ('s, 'e, 'c) System.t -> 'phase t -> 'phase t

  val register_all : 'phase t -> World.t -> unit
  val run          : 'phase t -> World.t -> float -> unit
  val run_by_filter :
    filter:(System.kind -> bool) ->
    'phase t -> World.t -> float -> unit

  val phases : 'phase t -> 'phase list
end
```

`run` and `register_all` take `World.t` — identical to `Eon_ecs.Pipeline.S`.
`World_cap` wrapping is entirely internal to the pipeline; `Progress` and `Loop`
never see it and require no changes. See §7.4.

---

## 7. Execution Algorithm

### 7.1 Phase-level loop

```ocaml
let run t (world : World.t) dt =
  let ro = world |> World_cap.wrap |> World_cap.readonly in
  (* World_cap.wrap and readonly happen once — zero cost per phase *)
  List.iter (fun phase ->
    match Hashtbl.find_opt t.systems phase with
    | None -> ()
    | Some systems ->
      Executor.run_all
        (List.map (fun s -> fun () -> s.update ro dt)
           (List.rev systems)))
    (sorted_phases t)
```

No phase-kind check. No branching. Every phase dispatches via `Executor` —
`Sequential` gives the sequential fallback, `Domain_pool` gives parallelism.

### 7.2 `run_by_filter`

Same loop, but the jobs list only contains systems that pass `filter s.kind`.
`run_all` still blocks until all filtered jobs complete.

### 7.3 Structural safety

No additional sync step is needed. From [thread_safety_design.md §6](thread_safety_design.md):
structural mutations (`add_component`, `remove_component`, `destroy_entity`)
are confined to `on_*` handlers that fire during `Buses.collect` /
`Buses.drain` — both outside `Progress.tick` / the parallel phase window.
When `Executor.run_all` receives its job list, the world is structurally
frozen.

### 7.4 ECS chain preservation — `World_cap` is pipeline-internal

`Progress` and `Loop` both work with `World.t` and call `Pipeline.run world
dt` — identical to the sequential pipeline. `World_cap.wrap` and
`World_cap.readonly` happen inside `run`, invisible to callers above:

```
Loop (World.t)
  → Progress.tick (World.t)
    → Pipeline.run (World.t)          ← same signature as Eon_ecs.Pipeline
        → World_cap.wrap / readonly   ← internal; callers never see World_cap
          → Executor.run_all          ← systems see ro World_cap.t
```

Similarly, `register_all` wraps internally so that handler closures capture
`rw World_cap.t` at registration time — pointing at the same underlying
mutable `World.t`, so they always see current state when dispatched at drain.

The only new public type is `Eon_engine.System`, whose `update` takes
`World_cap.ro World_cap.t`. That is the deliberate contract of the parallel
pipeline — not a breakage of the chain above it.

---

## 8. Bus Emit Under Parallelism

> **WIP — direction agreed, implementation approach not yet decided.** The
> problem and constraints are settled (§8.1–8.4). The open question is whether
> to add a `Mutex` directly to the bus or use an injectable `LOCK` functor to
> keep `eon_ecs` mutex-free (§8.5). Both are correct; the trade-off is API
> surface vs. philosophical purity.

Systems running in parallel may call `emit` on a bus. The bus queue is a
mutable OCaml value; concurrent appends from multiple Domains can corrupt it.
The fix is a **`Mutex` on `emit`** — self-contained in the bus, no changes to
the Executor, Pipeline, World, or system interface.

### 8.1 The straightforward approach

Each bus holds one `Mutex.t`. `emit` locks it, appends the message, unlocks.

```ocaml
type 'a t = {
  queue : 'a Queue.t;
  mutex : Mutex.t;
  (* ... *)
}

let emit bus msg =
  Mutex.lock bus.mutex;
  Queue.push msg bus.queue;
  Mutex.unlock bus.mutex
```

The Mutex only guards `emit`. `drain`, `collect`, and handler registration all
run sequentially — outside the parallel phase window — and need no locking.

### 8.2 Why not per-worker local buffers

The alternative — each worker accumulates emits into a local buffer, merged
at the phase barrier — cannot be contained inside the Executor. The Executor
only controls when jobs run; it has no hook between a system and the bus it
fetches from the World. Intercepting `emit` requires either wrapping the World
passed to each worker, adding `Domain.DLS` checks inside the bus, or changing
the system interface. All three spread the complexity across multiple modules.

### 8.3 Performance

An uncontended `Mutex.lock`/`unlock` on OCaml 5 is a single atomic CAS,
roughly 10–30 ns. Emit is a cold-path call — systems emit a handful of
messages per frame, not inside the hot iteration loop. In a PoE2-scale game
(400 enemies, 150 projectiles, 300 status-effected entities, 800 animated
entities) the parallel `Read_only` phase emits roughly 1650 messages per
frame. At 20 ns each that is **~33 µs out of a 16 ms budget** — 0.2%,
unmeasurable in practice.

### 8.4 Ordering

The order in which concurrently emitted messages land in the queue is
intentionally unspecified and irrelevant. Each system emits logically
independent messages (a Move intent, a Damage event, an animation frame
update) — subscribers handle their own message types and do not depend on
interleaving order with other systems in the same phase.

### 8.5 Open: injectable `LOCK` functor vs. hard-coded `Mutex`

> **Not yet decided.**

The straightforward approach (§8.1) adds a `Mutex` directly to the bus,
which means `eon_ecs` takes a dependency on `Mutex` even in purely sequential
use. This is technically harmless — `Mutex` is part of the OCaml stdlib — but
it breaks the philosophy that `eon_ecs` never imposes a concurrency solution.

The alternative is a thin `LOCK` functor seam in `eon_ecs`:

```ocaml
(* bus.mli *)
module type LOCK = sig
  type t
  val create : unit -> t
  val lock   : t -> unit
  val unlock : t -> unit
end

module No_lock : LOCK  (* all ops are no-ops; zero runtime cost after inlining *)
```

```ocaml
(* single_bus.ml *)
module Make (L : LOCK) : BUS = struct
  type 'a t = { queue : 'a Queue.t; lock : L.t; ... }
  let emit bus msg =
    L.lock bus.lock;
    Queue.push msg bus.queue;
    L.unlock bus.lock
end

module Default = Make(No_lock)  (* consistent with System.Default, Pipeline.Default, etc. *)
```

`Double_bus` follows the exact same pattern — `Make(L : LOCK)` with `module
Default = Make(No_lock)`. The lock only guards `emit` there too; `drain`'s
buffer swap runs sequentially outside the parallel phase window and needs no
locking.

`eon_engine` then injects the real `Mutex` into both:

```ocaml
module Mutex_lock : Eon_ecs.Bus.LOCK = struct
  type t = Mutex.t
  let create = Mutex.create
  let lock   = Mutex.lock
  let unlock = Mutex.unlock
end

module Single_bus_mt = Eon_ecs.Single_bus.Make(Mutex_lock)
module Double_bus_mt = Eon_ecs.Double_bus.Make(Mutex_lock)
```

For this to work `LOCK` must be reachable from outside `eon_ecs`. It should
be exported via `Bus` in `eon_ecs.mli` — `LOCK` is a bus concern, and `Bus`
already owns `BUS`:

```ocaml
(* eon_ecs.mli *)
module Bus : sig
  module type BUS  = ...
  module type LOCK = sig
    type t
    val create : unit -> t
    val lock   : t -> unit
    val unlock : t -> unit
  end
  module No_lock : LOCK
end
```

`eon_engine` then references it as `Eon_ecs.Bus.LOCK`, keeping everything
bus-related in one place in the public API.

**`eon_ecs.ml`/`eon_ecs.mli` alias update (mandatory).** Currently the
top-level aliases point at the bus modules directly:

```ocaml
module Signals  = Single_bus   (* currently satisfies BUS *)
module Events   = Double_bus
module Commands = Single_bus
```

After the refactor `Single_bus` and `Double_bus` are functor containers, no
longer satisfying `BUS` themselves. The aliases must be updated to the
`Default` instances:

```ocaml
module Signals  = Single_bus.Default
module Events   = Double_bus.Default
module Commands = Single_bus.Default
```

The same update applies to the corresponding type annotations in
`eon_ecs.mli`. Everything downstream — `System.Default`, `Pipeline.Default`,
`Loop.Default` — picks up `Signals`, `Events`, `Commands` transitively and
requires no further changes.

**Trade-off:**

| | Hard-coded `Mutex` | Injectable `LOCK` |
|---|---|---|
| `eon_ecs` mutex-free | No | Yes |
| Philosophy consistent | Borderline | Fully consistent |
| Added API surface | None | `LOCK` sig + `No_lock` + `Make` functor per bus |
| `Default = Make(No_lock)` keeps BC | — | Yes, consistent with rest of eon_ecs |
| `No_lock` runtime cost | — | Zero after inlining |

The injectable approach is the right call if we care about `eon_ecs` being a
genuinely mutex-free library. The added surface is small and stable.

---

## 9. Open Decisions

### 9.1 `RO`/`RW` World Views (phantom capabilities)

**Decided: ship with the first parallel pipeline, using Option A.**

Implemented as `Eon_engine.World_cap` — a dedicated module wrapping
`Eon_engine.World.t` with phantom capability types. `ro` and `rw` are aliases
for polymorphic variant types so switching to full phantom contravariance
(Option B) later is a one-line change with zero call-site impact:

```ocaml
type ro = [ `R ]
type rw = [ `R | `W ]
```

A one-way `readonly : rw t -> ro t` downgrade is provided explicitly. The
pipeline receives `rw t`, calls `readonly` once at the start of `run`, and
passes `ro t` into every system `update`. Full design is captured in
[thread_safety_design.md §7](thread_safety_design.md).

### 9.2 Concrete `Executor` implementations

Ship `Sequential` first (always). Then decide:

- **OCaml 5 `Domain_pool`:** natural fit given OCaml 5-only baseline. `n`
  domains created once at pipeline construction; `run_all` distributes jobs
  via a `Mutex`-guarded deque and waits for all workers.
- **`Thread_pool`:** POSIX threads via `Thread`; broader compatibility but
  OCaml 5 GIL still limits true CPU parallelism for compute-bound tasks.
- **User-supplied executor:** should the `Executor` module type be a
  documented public extension point from day one? If so, document the
  exception-safety contract (`run_all` must not swallow exceptions from jobs).

---

## 10. Invariants (Summary)

The parallel execution is safe iff:

1. **Phases are sequential** — each `Executor.run_all` returns before the
   next phase begins. (`Pipeline.run` enforces this structurally.)
2. **All system `update` functions are read-only** — enforced at compile time
   by `World_cap.ro World_cap.t` (§9.1, [thread_safety_design.md §7](thread_safety_design.md)).
3. **No structural mutations are in flight during `Progress.tick`** — they
   are confined to `on_*` handlers in `collect`/`drain`
   ([thread_safety_design.md §6](thread_safety_design.md)).
4. **Bus `emit` is `Mutex`-protected; dispatch stays sequential** (§8).

All four invariants are structural or compile-time guarantees — none require
user promises or tag honesty.

# Parallel Pipeline Execution — `eon_engine`

## Status

**IMPLEMENTED (ecs-021).** Sequential executor, parallel pipeline, engine buses — all shipped, tested, and committed.

**IMPLEMENTED (ecs-022).** `Executor.Domain_pool` — persistent OCaml 5 Domain
worker pool. Shipped, tested, and benchmarked. §4.2 is the authoritative design;
§9.2 is resolved.

**IMPLEMENTED (ecs-023).** `World_cap` removed; phantom `ro`/`rw` capability
types moved directly into `World`. Developers now see `World.ro World.t` /
`World.rw World.t` instead of `World.ro World.t`.

The concurrency philosophy, invariants, and frame-order constraints live in
[thread_safety_design.md](thread_safety_design.md). This document is the
authoritative reference for the parallel pipeline design.

---

## 1. Scope and Relationship to Core

`eon_ecs` is strictly sequential and stays that way. The parallel pipeline is
entirely an `eon_engine` concern that **builds upon** the core rather than
replacing it:

- **`Eon_engine.System.Make(Core_system)`** wraps `Core_system.make_reactive`
  internally. The user's closures receive `World.ro World.t` / `World.rw World.t`
  typed views; the wrapper stores `update_kind` alongside the embedded core. The
  returned type is the engine system type — a new record, not `Core_system.t`.
- **`Eon_engine.Pipeline.Make(System)(Executor)`** is the single pipeline for
  engine systems. `Executor.Sequential` gives sequential execution; `Executor.Domain_pool`
  gives parallel execution. Same system definitions work with both — swap the
  executor, not the system code.

The only `eon_ecs` change is extracting `topo_sort` into a public
`Eon_ecs.Dependency_graph` primitive (§2 below). No changes to `Eon_ecs.System.S`,
`Eon_ecs.Pipeline.S`, `Eon_ecs.Progress`, or `Eon_ecs.Loop`.

```
eon_engine (new modules — extends, does not replace)
  Eon_engine.World (ro/rw phantom types)       ← phantom capability types (ecs-023)
  Eon_engine.Bus / Single_bus / Double_bus     ← mutex-on-emit bus implementations
  Eon_engine.Executor.S / Sequential           ← threading-substrate seam
  Eon_engine.System.make                       ← wraps Eon_ecs.System.make_reactive + World.ro/rw
  Eon_engine.Pipeline.Make(System)(Executor)   ← parallel dispatch; satisfies Pipeline.S
  Eon_engine.Loop_buses                        ← BUSES module for engine bus collect/drain

eon_ecs (one additive change only)
  Eon_ecs.Dependency_graph                     ← extracted topo-sort primitive (new public module)
  Eon_ecs.Pipeline.Make                        ← refactored to delegate to Dependency_graph
  (System, Pipeline.S, Progress, Loop, buses — all unchanged)
```

This is the established extension pattern in the codebase: `Eon_engine.World`
wraps `Eon_ecs.World` with typed component descriptors; `Eon_engine.System.make`
wraps `Eon_ecs.System.make_reactive` with `World.ro`/`World.rw` capabilities. The core
is never replaced — it is wrapped and extended.

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
`World.ro World.t`. Since the type system enforces read-only at compile
time, every phase's updates are safe to run in parallel — a per-phase tag
would only re-state what the type already guarantees.

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

A sub-module `Domain_pool` containing a `Make` functor, consistent with the
codebase convention that all functors are named `Make`:

```ocaml
module Domain_pool : sig
  val recommended_size : unit -> int
  module Make (Config : sig val size : int end) : S
end
```

OCaml 5 Domains map 1:1 to OS threads; the OS scheduler pins them to CPU cores,
giving true CPU parallelism with no GIL and no cooperative yielding.

**Domain 0 is the main program domain** and counts toward the core budget.
`Domain.recommended_domain_count ()` (OCaml 5.1+) returns total recommended
domains including Domain 0 — so the right worker count to fill all cores without
oversubscribing is:

```ocaml
let recommended_size () = max 1 (Domain.recommended_domain_count () - 1)
```

For a game, leave extra headroom for the render thread, audio, and OS scheduler:

```ocaml
max 1 (Executor.Domain_pool.recommended_size () - 1)
```

`Domain_pool.recommended_size` is exported so callers can use a hardware-aware
default without recomputing this arithmetic themselves.

Usage at pipeline construction:

```ocaml
(* Explicit size *)
module Pipeline =
  Eon_engine.Pipeline.Make
    (Eon_engine.System.Default)
    (Eon_engine.Executor.Domain_pool.Make(struct let size = 4 end))

(* Hardware-aware default — fills all cores minus main domain *)
module Pipeline =
  Eon_engine.Pipeline.Make
    (Eon_engine.System.Default)
    (Eon_engine.Executor.Domain_pool.Make(
      struct let size = Eon_engine.Executor.Domain_pool.recommended_size () end))
```

`Config.size` worker domains are spawned once when the module is first touched.
Each domain runs a persistent worker loop: sleep on a `Condition.t` when the
job queue is empty, pop and run one job at a time, signal the caller when
`pending` reaches zero.

#### Internal state

```ocaml
type pool = {
  mutex     : Mutex.t;
  not_empty : Condition.t;   (* workers sleep here when queue is empty *)
  all_done  : Condition.t;   (* run_all caller waits here *)
  queue     : (unit -> unit) Queue.t;
  pending   : int ref;       (* queued + in-flight jobs *)
  exns      : exn list ref;  (* exceptions captured from workers *)
  shutdown  : bool ref;
}
```

#### Worker loop

```ocaml
let worker_loop pool =
  let rec loop () =
    let job = Mutex.protect pool.mutex (fun () ->
      while Queue.is_empty pool.queue && not !(pool.shutdown) do
        Condition.wait pool.not_empty pool.mutex
      done;
      if !(pool.shutdown) && Queue.is_empty pool.queue then None
      else Some (Queue.pop pool.queue))
    in
    match job with
    | None -> ()   (* shutdown *)
    | Some f ->
      (try f ()
       with e ->
         Mutex.protect pool.mutex (fun () ->
           pool.exns := e :: !(pool.exns)));
      Mutex.protect pool.mutex (fun () ->
        decr pool.pending;
        if !(pool.pending) = 0 then Condition.signal pool.all_done);
      loop ()
  in
  loop ()
```

#### `run_all`

```ocaml
let run_all jobs =
  match jobs with
  | [] -> ()
  | _ ->
    Mutex.protect pool.mutex (fun () ->
      pool.pending := List.length jobs;
      List.iter (fun f -> Queue.push f pool.queue) jobs;
      List.iter (fun _ -> Condition.signal pool.not_empty) jobs);
    Mutex.protect pool.mutex (fun () ->
      while !(pool.pending) > 0 do
        Condition.wait pool.all_done pool.mutex
      done;
      match !(pool.exns) with
      | [] -> ()
      | e :: _ ->
        pool.exns := [];
        raise e)
```

Exception contract: `run_all` re-raises the first captured worker exception
(non-deterministic which one if multiple jobs raise) after all jobs have
completed. Other exceptions are discarded. This satisfies "must not swallow
exceptions" while keeping the API synchronous. See §9.2.

#### Outer module structure

```ocaml
module Domain_pool = struct
  let recommended_size () =
    max 1 (Domain.recommended_domain_count () - 1)

  module Make (Config : sig val size : int end) : S = struct
    let pool = make_pool ()
    let () =
      for _ = 1 to Config.size do
        ignore (Domain.spawn (fun () -> worker_loop pool))
      done
    let run_all jobs = run_pool pool jobs
  end
end
```

`Domain_pool` is a plain module (not itself a functor) so `recommended_size` has
a stable call path. `Make` is the functor, consistent with the codebase convention
that all functors are named `Make`. The executor module boundary is the only place
a `Domain` ever appears in the pipeline code.

---

## 5. `Eon_engine.System` — Wraps Core System with World Capability Types

The engine's system module **wraps** any `Eon_ecs.System.S` implementation,
following the same pattern as `Eon_engine.World` wrapping `Eon_ecs.World`:
embed the core type, delegate to it, add engine-specific capabilities.

`Eon_engine.System` is a **functor** over `Eon_ecs.System.S`:

```ocaml
module Make (Core_system : Eon_ecs.System.S) : S

(* Wired in the composition root with engine buses: *)
module Default : S
(* = Make(Eon_ecs.System.Make(Eon_engine.Signals)(Eon_engine.Events)(Eon_engine.Commands)) *)
```

`Default` is wired with engine bus modules (`Signals`, `Events`, `Commands` — the
engine aliases for `Single_bus` / `Double_bus`), not with `Eon_ecs.System.Default`
which uses the core buses. This ensures `attach` reads and registers against
`Eon_engine.Single_bus.t` / `Double_bus.t` instances from the world, not
`Eon_ecs.Single_bus.t` ones. Using `Eon_ecs.System.Default` as `Core_system` would
cause a bus type mismatch at `register_all` time.

`Make` accepts any `Eon_ecs.System.S` — custom buses, custom kinds, whatever the
developer constructs.

### 5.1 Implementation structure

The engine system record stores user handlers directly alongside `update_kind`.
This avoids the `Eon_ecs.World.t`/`World.rw World.t` mismatch that would arise from embedding
a `Core_system.t` (which expects `Eon_ecs.World.t`) inside a type whose handlers
expect `World.rw World.t`:

```ocaml
(* eon_engine/system.ml — inside Make(Core_system) *)
type ('s, 'e, 'c) t = {
  register    : Eon_ecs.World.t -> unit;
  update_kind : update_kind;
  kind        : kind;
  on_signal   : World.rw World.t -> 's -> unit;
  on_event    : World.rw World.t -> 'e -> unit;
  on_command  : World.rw World.t -> 'c -> unit;
}
```

`update_ro` and `update_rw` dispatch from `update_kind` directly. `attach`
(called by `register_all`) reads bus instances from world services and wires the
stored handlers as subscribers — the same service-locator pattern as
`Eon_ecs.System.attach_handlers`. `register` is a no-op placeholder; component
pre-registration happens at world setup time via `World.register`, not per-system.
The `.mli` exports `module type S` (§5.2) with an abstract `type t` — the record
fields are not visible to callers.

### 5.2 Public API — `S` and `DISPATCH`

Two module types govern the system module:

- **`module type S`** — user-facing. Contains only `make`, `type t`, and `type kind`.
  `eon_engine.mli` re-exports `System.Default` constrained to this type; game code
  sees `make` and nothing else — `is_parallel`, `update_ro`, etc. never appear.
- **`module type DISPATCH`** — pipeline-internal. Extends `S` with the dispatch
  operations `Pipeline.Make` needs. `Pipeline.Make` takes `System : System.DISPATCH`,
  not `System : System.S`. `system.mli` exports both.

```ocaml
(* eon_engine/system.mli *)

type update_kind =
  | Parallel  of (World.ro World.t -> float -> unit)
  | Exclusive of (World.rw World.t -> float -> unit)

(** User-facing interface — the only part game code ever sees. *)
module type S = sig
  type ('s, 'e, 'c) t
  type kind

  val make :
    ?on_signal:(World.rw World.t -> 's -> unit) ->
    ?on_event:(World.rw World.t -> 'e -> unit) ->
    ?on_command:(World.rw World.t -> 'c -> unit) ->
    ?kind:kind ->
    update_kind ->
    ('s, 'e, 'c) t
end

(** Pipeline-internal interface. [Pipeline.Make] takes [System : DISPATCH]. *)
module type DISPATCH = sig
  include S
  val is_parallel : ('s, 'e, 'c) t -> bool
  val update_ro   : ('s, 'e, 'c) t -> World.ro World.t -> float -> unit
  val update_rw   : ('s, 'e, 'c) t -> World.rw World.t -> float -> unit
  val register    : ('s, 'e, 'c) t -> Eon_ecs.World.t -> unit
  val attach      : ('s, 'e, 'c) t -> Eon_ecs.World.t -> unit
end

module Make (Core_system : Eon_ecs.System.S) : DISPATCH
module Default : DISPATCH
```

`update_kind` lives at the top level of `system.mli` — outside the module types —
so it is shared across all functor instantiations. `Parallel` and `Exclusive`
constructors are the same type regardless of which `Core_system` was used.

`update_kind` determines how the system's update function is dispatched:
- `Parallel` — receives `World.ro World.t`, runs via `Executor.run_all`
- `Exclusive` — receives `World.rw World.t`, runs sequentially after parallel systems

The type system enforces the invariant: `Parallel` closures can't write
(`World.ro World.t` doesn't expose write operations), and `Exclusive` closures
are always dispatched sequentially by the pipeline.

`eon_engine.mli` constrains the public view — `System.Make` returns `DISPATCH`
(so it can be passed to `Pipeline.Make`), while `System.Default` is constrained
to `S` (game code sees only `make`):

```ocaml
(* eon_engine.mli — System section *)
module System : sig
  module type S        = System.S
  module type DISPATCH = System.DISPATCH
  module Make (C : Eon_ecs.System.S) : System.DISPATCH  (* full type; for Pipeline.Make *)
  module Default : System.S                              (* constrained; hides dispatch ops *)
end
```

Game code sees `System.Default.make` and nothing else. Advanced users building
custom pipelines call `System.Make(Core)` — which returns `DISPATCH` and can be
passed directly to `Pipeline.Make`. For a custom executor with the default system
configuration, use `System.Make(Eon_ecs.System.Make(Signals)(Events)(Commands))`
explicitly rather than `System.Default`. The common case — `System.Default.make`
for defining systems and `Pipeline.Default` for running them — requires zero
knowledge of `DISPATCH`.

### 5.3 `make` — stores handlers at construction time

```ocaml
(* eon_engine/system.ml — inside Make(Core_system) *)

let make ?(on_signal  = fun _ _ -> ())
         ?(on_event   = fun _ _ -> ())
         ?(on_command = fun _ _ -> ())
         ?(kind = default_kind)
         update_kind =
  { register = (fun _ -> ()); update_kind; kind; on_signal; on_event; on_command }
```

`make` is O(1) — it stores the user's closures directly without wrapping them.
Dispatch is straightforward:
- `update_ro` — extracts the `Parallel` closure from `update_kind`, passes `World.ro World.t`
- `update_rw` — extracts the `Exclusive` closure from `update_kind`, passes `World.rw World.t`
- `attach` — subscribes `on_*` closures to bus instances read from world services

The default `kind` is borrowed from `Core_system.make_reactive ()` so that
`System.Default.make` inherits the same default kind as the underlying core system.

### 5.4 Usage — Parallel and Exclusive systems

```ocaml
module System   = Eon_engine.System.Default
(* Sequential execution — swap Domain_pool.Make for parallelism, no system changes *)
module Pipeline = Eon_engine.Pipeline.Make(System)(Eon_engine.Executor.Sequential)

(* Parallel system — read-only update, writes via on_command *)
let physics =
  System.make
    ~on_command:(fun rw cmd -> match cmd with
      | Move (e, vel) -> World.set_component rw e Velocity.component vel
      | _ -> ())
    (Parallel (fun ro dt ->
      (* ro : World.ro World.t — writes are compile-time errors *)
      Query.iter (fun view -> ...)))

(* Exclusive system — read-write update, runs sequentially *)
let inventory_ui =
  System.make
    (Exclusive (fun rw dt ->
      (* rw : World.rw World.t — writes allowed *)
      World.set_component rw entity Inventory.component new_inv))

let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Physics
  |> Pipeline.add_phase `UI
  |> Pipeline.before ~earlier:`Physics ~later:`UI
  |> Pipeline.add_system `Physics physics
  |> Pipeline.add_system `UI inventory_ui

Pipeline.register_all pipeline world;
Pipeline.run pipeline world dt
```

### 5.5 Custom buses — functor composition

```ocaml
(* Custom buses — priority queues, ring buffers, whatever *)
module My_core   = Eon_ecs.System.Make(My_signals)(My_events)(My_commands)
module My_system = Eon_engine.System.Make(My_core)

let s = My_system.make (Parallel (fun ro dt -> ...))
(* core uses My_signals/My_events/My_commands internally *)
```

### 5.6 Non-reactive and Exclusive systems

Systems that write world state directly during `update` (UI, inventory, debug
tools) use `Exclusive`:

```ocaml
(* module System = Eon_engine.System.Default *)
let inventory_ui =
  System.Default.make
    (Exclusive (fun rw dt ->
      (* rw : World.rw World.t — writes allowed *)
      World.set_component rw entity Inventory.component new_inv))
```

Systems that only read use `Parallel`:

```ocaml
let tooltip_renderer =
  System.Default.make
    (Parallel (fun ro dt ->
      Query.iter (fun view -> ...)))
```

Both work with the engine pipeline. `Parallel` systems run via `Executor`
(concurrent with `Domain_pool`, sequential with `Sequential`). `Exclusive`
systems run sequentially after all parallel systems in the phase complete.

---

## 6. `Eon_engine.Pipeline.Make` — Parallel Dispatch via Executor

The engine pipeline is a **genuinely new pipeline** that extends the core with
parallel dispatch. It reuses `Eon_ecs.Dependency_graph` for phase ordering and
dispatches system `update_ro` closures via `Executor.run_all`.

> Takes `System : Eon_engine.System.DISPATCH` — the pipeline-internal interface from §5.2.

```ocaml
module Make
    (System   : Eon_engine.System.DISPATCH)
    (Executor : Eon_engine.Executor.S)
  : sig
  type 'phase t
  type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
  type kind = System.kind

  val create     : unit -> 'phase t
  val add_phase  : 'phase -> 'phase t -> 'phase t
  val before     : earlier:'phase -> later:'phase -> 'phase t -> 'phase t
  val after      : later:'phase  -> earlier:'phase -> 'phase t -> 'phase t
  val add_system : 'phase -> ('s, 'e, 'c) system_t -> 'phase t -> 'phase t

  val register_all : 'phase t -> Eon_ecs.World.t -> unit
  val run          : 'phase t -> Eon_ecs.World.t -> float -> Eon_ecs.World.t
  val run_by_filter :
    filter:(kind -> bool) ->
    'phase t -> Eon_ecs.World.t -> float -> Eon_ecs.World.t

  val phases : 'phase t -> 'phase list
end
```

The explicit `type system_t` and `type kind` aliases mean the output satisfies
`Eon_ecs.Pipeline.S with type kind = Eon_ecs.System.kind`. This lets
`Eon_ecs.Progress.Make(Eon_engine.Pipeline.Default)` work directly — no adapter
needed.

`run` and `register_all` take `World.rw World.t`. `Progress` and `Loop` pass
the `rw` world through; capability management is internal to the pipeline.
See §7.4.

The pipeline uses `Eon_ecs.Dependency_graph` internally for phase ordering —
the same primitive used by `Eon_ecs.Pipeline.Make`. No duplication of topo-sort
logic across the package boundary.

---

## 7. Execution Algorithm

### 7.1 Phase-level loop

```ocaml
let run t (world : World.rw World.t) dt =
  let ro = World.readonly world in
  (* readonly is zero-cost — only the phantom type changes *)
  List.iter (fun phase ->
    match Hashtbl.find_opt t.systems phase with
    | None -> ()
    | Some systems ->
      let parallel, exclusive =
        List.partition (fun s -> System.is_parallel s) (List.rev systems)
      in
      (* 1. Parallel systems via Executor *)
      Executor.run_all
        (List.map (fun s -> fun () -> System.update_ro s ro dt) parallel);
      (* 2. Exclusive systems sequentially *)
      List.iter (fun s -> System.update_exclusive s world dt) exclusive)
    (Dependency_graph.topo_sort t.graph)
```

Two-step dispatch per phase:

1. **Parallel systems** — partitioned by `update_kind`, dispatched via
   `Executor.run_all`. With `Sequential`, they run one by one. With
   `Domain_pool`, they run concurrently. All receive `World.ro World.t`.

2. **Exclusive systems** — run sequentially AFTER all parallel systems in the
   phase complete. Receive `World.rw World.t`. The phase barrier guarantees no
   parallel system is running when an exclusive system writes.

This is the same model Bevy calls "exclusive systems." The type system enforces
the invariant: `Parallel` closures can't write (ro), `Exclusive` closures can't
run concurrently (pipeline dispatches them sequentially).

With `Executor.Sequential`, both steps reduce to `List.iter` — no true
concurrency occurs. The two-step structure is kept anyway: it preserves the
parallel-then-exclusive ordering guarantee regardless of executor. An `Exclusive`
system that relies on seeing a phase's `Parallel` work completed before it runs
behaves identically under `Sequential` and `Domain_pool`. Merging into a single
pass would break this by making the order registration-dependent, creating a
latent bug for anyone swapping executors.

### 7.2 `run_by_filter`

Same loop, but the systems list is filtered by `filter s.kind` before
partitioning. The parallel/exclusive dispatch within a filtered phase is
unchanged.

### 7.3 Structural safety

No additional sync step is needed. From [thread_safety_design.md §6](thread_safety_design.md):
structural mutations (`add_component`, `remove_component`, `destroy_entity`)
are confined to `on_*` handlers that fire during `Buses.collect` /
`Buses.drain` — both outside `Progress.tick` / the parallel phase window.
When `Executor.run_all` receives its job list, the world is structurally
frozen.

### 7.4 ECS chain preservation — one engine system type, two executors

`Eon_engine.System.Default.t` is its own record type (storing `update_kind`
alongside the embedded core). It is **not** the same type as
`Eon_ecs.System.Default.t` and does not satisfy `Eon_ecs.System.S`. Engine
systems always go through `Eon_engine.Pipeline.Make`; the executor controls
whether dispatch is sequential or parallel:

```
Eon_engine.System.Default.make → ('s, 'e, 'c) Eon_engine.System.Default.t
  │
  └──→ Eon_engine.Pipeline.Make(System)(Executor)
         Executor.Sequential        ← sequential dispatch
         Executor.Domain_pool.Make  ← parallel dispatch
         World.readonly called once at start of run
```

Swapping executors requires no system changes — the same `System.Default.make`
call works with both. `Exclusive` systems run sequentially in both cases; the
executor only controls dispatch of `Parallel` systems.

```
Loop (World.rw World.t)
  → Progress.Make(Engine_pipeline).tick (World.rw World.t)
    → Engine.Pipeline.run_by_filter (World.rw World.t)
        → Executor.run_all             ← Parallel systems see World.ro World.t
        → sequential Exclusive dispatch ← Exclusive systems see World.rw World.t
```

Pure core code uses `Eon_ecs.Pipeline.Make(Eon_ecs.System.Default)` directly
— no engine involvement.

---

## 8. Bus Emit Under Parallelism

**Decision: `Eon_engine` owns its own bus implementations.** `eon_ecs` buses
are left completely untouched — no `LOCK` functor, no `Make` refactor, no
alias updates. The engine layer provides mutex-aware `Single_bus` and
`Double_bus` that it uses for the parallel pipeline.

Systems running in parallel may call `emit` on a bus. The bus queue is a
mutable OCaml value; concurrent appends from multiple Domains can corrupt it.
The fix is a **`Mutex` on `emit`** — self-contained in the bus, no changes to
the Executor, Pipeline, World, or system interface.

### 8.1 `Eon_engine.Bus`

`Eon_engine` defines its own `Bus.S` signature (identical to `Eon_ecs.Bus.BUS`
for now — a clean extension point if engine buses ever need engine-specific
capabilities) and provides two standalone implementations:

```ocaml
(* eon_engine/bus.mli *)
module type S = Eon_ecs.Bus.BUS

module Single_bus : S  (* same-frame; drain = collect; mutex on emit *)
module Double_bus : S  (* next-frame; emit → next queue; mutex on emit *)
```

Each module **embeds** the corresponding `Eon_ecs` bus type and adds a
`Mutex.t`. `emit` is the only operation that locks; all other operations
delegate to the inner bus and run sequentially outside the parallel phase
window. This is the same pattern `Eon_engine.System.Make` uses — embed the
core, add one capability on top:

```ocaml
(* eon_engine/single_bus.ml *)
type 'a t = { inner : 'a Eon_ecs.Single_bus.t; mutex : Mutex.t }

let create ()  = { inner = Eon_ecs.Single_bus.create (); mutex = Mutex.create () }
let emit t msg = Mutex.lock t.mutex; Eon_ecs.Single_bus.emit t.inner msg; Mutex.unlock t.mutex
let on t h     = Eon_ecs.Single_bus.on t.inner h
let collect t  = Eon_ecs.Single_bus.collect t.inner
let drain      = collect
```

`Double_bus` follows the same embedding pattern with `Eon_ecs.Double_bus.t` as
the inner type; `emit` delegates to the inner bus's `emit` under the mutex;
`drain` delegates to the inner bus's `drain` — both sequentially, no locking
needed.

Bus instances are threaded through the world as services — the same
service-locator pattern as the core. Before calling `register_all`, the user
registers engine bus instances in the world under `` `Signals ``, `` `Events ``,
`` `Commands ``. `register_all` calls `System.attach s world` on each system;
`attach` reads those instances from world services and registers handlers onto
them. Identical to `Eon_ecs.System.attach_handlers` — same mechanism, engine bus
types instead of core bus types.

The engine also provides `Eon_engine.Loop_buses` (analogous to
`Eon_ecs.Loop_default_buses`) — a `BUSES` module that reads engine bus instances
from world services to drive `collect` / `drain` in `Loop.Make`.

`eon_ecs.Single_bus` and `eon_ecs.Double_bus` are never touched.

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
entities) the parallel phase emits roughly 1650 messages per frame. At 20 ns
each that is **~33 µs out of a 16 ms budget** — 0.2%, unmeasurable in practice.

### 8.4 Ordering

The order in which concurrently emitted messages land in the queue is
intentionally unspecified and irrelevant. Each system emits logically
independent messages (a Move intent, a Damage event, an animation frame
update) — subscribers handle their own message types and do not depend on
interleaving order with other systems in the same phase.

### 8.5 Re-export discipline

`Eon_engine` is the single import for game code (see `eon_engine_design.md §3.4`).
`Single_bus` and `Double_bus` are engine-owned implementations, so they are
exported directly from `eon_engine.mli` — not re-exported from `eon_ecs`:

```ocaml
(* eon_engine.mli — bus exports *)
module Bus        = Bus          (* Bus.S signature *)
module Single_bus = Single_bus   (* engine's mutex-aware implementation *)
module Double_bus = Double_bus   (* engine's mutex-aware implementation *)
```

`Eon_ecs.Single_bus` and `Eon_ecs.Double_bus` remain the no-Mutex sequential
implementations and are not exposed to game code at the engine layer.

---

## 9. Open Decisions

### 9.1 `RO`/`RW` World Views (phantom capabilities)

**Decided: ship with the first parallel pipeline, using Option A.**

**Decided (ecs-021): separate `World_cap` module. Revised (ecs-023): folded
into `World` directly.**

`World.ro` and `World.rw` are the phantom capability types. `World.t` is now
`'perm World.t`; the pipeline receives `World.rw World.t`, calls `World.readonly`
once at the start of `run`, and passes `World.ro World.t` to every parallel
system `update`. `World_cap` no longer exists as a separate module.

```ocaml
type ro = [ `R ]
type rw = [ `R | `W ]
type 'perm t          (* phantom — underlying record unchanged *)
val readonly : rw t -> ro t   (* zero-cost identity, external "%identity" *)
```

Full design is captured in [thread_safety_design.md §7](thread_safety_design.md).

### 9.2 Concrete `Executor` implementations

**Decided (ecs-022).**

- **`Sequential`**: shipped with ecs-021. Always available; degrades to core
  sequential behaviour. Use as default and for testing.
- **`Domain_pool`**: ships with ecs-022. Concrete design in §4.2. `Thread_pool`
  is not planned — OCaml 5 GIL makes it inferior to `Domain_pool` for
  compute-bound work, and the `Executor.S` seam lets users supply their own
  if needed.
- **`Executor.S` is a public extension point**: `module type S` is exported in
  `executor.mli`. The only contract: `run_all` must not swallow exceptions from
  jobs — re-raise the first after all complete, or let the exception propagate
  synchronously. Implementations that swallow exceptions violate this contract
  and break caller error handling.
- **No `Thread_pool` planned**: OCaml 5 `Domain_pool` is the right choice for
  the OCaml 5-only baseline. `Thread` would share the GIL and offer no CPU
  parallelism for pure OCaml compute.

---

## 10. Invariants (Summary)

The parallel execution is safe iff:

1. **Phases are sequential** — each `Executor.run_all` returns before the
   next phase begins. (`Pipeline.run` enforces this structurally.)
2. **All `Parallel` system `update` functions are read-only** — enforced at
   compile time by `World.ro World.t` (§9.1,
   [thread_safety_design.md §7](thread_safety_design.md)). `Exclusive` systems
   receive `World.rw World.t` but run sequentially after all parallel systems
   in the phase complete.
3. **No structural mutations are in flight during `Progress.tick`** — they
   are confined to `on_*` handlers in `collect`/`drain`
   ([thread_safety_design.md §6](thread_safety_design.md)), or to `Exclusive`
   systems that run sequentially.
4. **Bus `emit` is `Mutex`-protected; dispatch stays sequential** (§8).

All four invariants are structural or compile-time guarantees — none require
user promises or tag honesty.

---

## 11. Exclusive System Variant — Part of ecs-021

The `update_kind` union type ships with the first parallel pipeline:

```ocaml
type update_kind =
  | Parallel  of (World.ro World.t -> float -> unit)
  | Exclusive of (World.rw World.t -> float -> unit)
```

The pipeline runs all `Parallel` systems in the current phase via
`Executor.run_all`, then runs all `Exclusive` systems in that phase one by one
— no scheduling logic, no conflict graph, no programmer declarations to trust.
The type guarantees `Parallel` systems never write and `Exclusive` systems
never run concurrently. This is the same model Bevy calls "exclusive systems."

The `on_*` handler model covers most write-at-update-time cases. Two clear
exceptions stand out:

**Non-reactive UI logic** — inventory management, skill tree allocation,
equipment changes, dialogue state. These systems read and write world state
directly in response to player input; there is no meaningful separation between
"observe" and "react", no parallelism to exploit, and no bus message that would
naturally carry the intent. Forcing them through the reactive pattern adds
indirection without benefit.

**Debugging and inspection tools** — world inspectors, entity browsers,
component viewers, live-edit tooling. These need arbitrary `rw` access to
traverse or modify any part of world state, are inherently sequential, and have
no reactive semantics at all. A bus-driven model would be nonsensical here.
Exclusive systems give them a clean, first-class slot in the pipeline without
requiring a separate escape hatch.

In both cases: sequential by construction, `rw` access guaranteed safe, no
scheduling machinery required.

---

## 12. Extension Pattern — Build Upon, Don't Replace

The engine follows the established wrapping pattern in the codebase:
`Eon_engine.World` wraps `Eon_ecs.World` with typed component descriptors;
`Eon_engine.System.make` wraps `Eon_ecs.System.make_reactive` with `World.ro`/`World.rw`
capabilities. The core is never replaced — it is wrapped and extended.

### 12.1 What "build upon" means concretely

| Core module | Engine relationship |
|---|---|
| `Eon_ecs.System.Make` | Used **inside** `Eon_engine.System.Make(Core_system)` to create the embedded core system |
| `Eon_ecs.Pipeline.Make` | Used directly for pure core code; engine systems use `Eon_engine.Pipeline.Make` instead |
| `Eon_ecs.Dependency_graph` | Used **inside** `Eon_engine.Pipeline.Make` for phase ordering |
| `Eon_ecs.Progress.Make` | Used **directly** with the engine pipeline — it satisfies `Pipeline.S` |
| `Eon_ecs.Loop.Make` | Used **directly** with `Progress.Make(Engine_pipeline)` and `Loop_buses` |

The engine adds capabilities that the core deliberately does not have:
`World.ro`/`World.rw` phantom types, mutex-aware buses, `Executor`-based parallel
dispatch. These are layered on top of the core, not baked into it.

### 12.2 Why this matters

`eon_ecs` stays minimal, unopinionated, and reusable. A developer who doesn't
need parallelism or phantom capabilities uses `eon_ecs` directly. A developer
who does uses `eon_engine` — which wraps `eon_ecs` rather than replacing it.

This is also the educational contract: `eon_engine` demonstrates how to properly
extend `eon_ecs` without replacing its modules. A developer building their own
extension follows the same pattern — embed the core type, delegate to it, add
their own capabilities on top.

### 12.3 Performance

Wrapping is zero-cost. `World.readonly` is `external "%identity"` — the phantom
type changes but the underlying record is untouched. At dispatch time:
- **Engine pipeline path**: `World.readonly` is called once at the start of `run`,
  then `update_ro` is called directly via `Executor.run_all`. Zero allocation per frame.

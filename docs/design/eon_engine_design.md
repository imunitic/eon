# Eon Engine Design Document

## Status

**Philosophy document.** Not a feature spec. Records the design principles, constraints, and architectural values that guide all `eon_engine` decisions. No implementation tasks derive from this document directly — it is the "why" behind every other design doc.

## 1. EON: The Idea and Principles

### 1.1 Core Philosophy

Eon ECS is a **minimal, deterministic, backend-agnostic entity-component-system runtime** for OCaml. The engine builds on this foundation to provide a higher-level, typed component registration API that maintains the same core principles while adding developer ergonomics.

### 1.2 Foundational Principles

**Minimalism**
- Core primitives only - no hidden magic or complex abstractions
- Every operation is explicit and observable
- Composition over inheritance via functors and module signatures

**Extensibility**
- Functorized modules and open polymorphic variant keys
- Backend-agnostic design allows swapping storage implementations
- Component registration is pluggable and type-safe

**Purity**
- Systems express intent; command handlers apply effects
- No hidden global state - all state is explicitly passed via World
- Idempotent operations ensure predictable behavior

**Determinism**
- Fixed/hybrid progress modes provide stable simulation behavior
- Bus ordering invariants guarantee predictable execution order
- Component registration is deterministic (automatic ID generation)

**Sensible defaults, open ceiling**
- Every layer provides a working default that covers most games with no configuration
- Defaults are never walls — complexity is always opt-in, not forced
- A simple game uses `World.create ()`, registers components, adds systems, runs the loop — nothing more needed
- A complex game with mixed tick rates, multi-world architecture, dedicated render worlds, or custom query backends can build that on the same primitives without fighting the engine
- This principle governs every future API decision: does this provide a sensible default while leaving the door open for complete optimization and scaling?

### 1.3 Bus Ordering Invariants

The ECS runtime enforces strict bus ordering:

1. **Collect**: Signals → Events → Commands
2. **Tick**: Progress.tick
3. **Drain**: Signals → Commands → Events
4. **Render**: Read-only work after drains

This ensures:
- Commands have same-frame effects via handlers
- Events are queued and become visible on double-buffer schedule
- Signals are transient notifications

### 1.4 Component Rules

- Register component names before `add_component`/`set_component`
- `World.get_component`, `set_component`, `remove_component` raise on unknown component names
- Component descriptors use phantom types for compile-time type safety

## 2. Eon ECS: Feature Complete Core

### 2.1 Current State

The `eon_ecs` package is **feature complete** and stable. It will almost never change unless bugs are found.

**Public API Boundary** (`eon_ecs/eon_ecs.mli`):
- `Entity_id`: Unique, generational entity identifiers
- `Component`: Typed component metadata and storage wrappers
- `World`: Central ECS state container
- `Query`: Iteration and counting helpers over component intersections
- `Clock`: Time sources for ECS loop
- `Bus`: Message bus implementation
- `System`: Reactive system registration and execution
- `Pipeline`: Phase graph with dependency ordering
- `Progress`: Variable/fixed/hybrid ticking
- `Loop`: Frame orchestrator (collect → tick → drain → render)
- `Signals`, `Events`, `Commands`: Message buses with explicit frame semantics

### 2.2 Query System

The ECS provides direct query functions:

```ocaml
val iter1 : World.t -> string -> (Entity_id.t -> 'a -> unit) -> unit
val iter2 : World.t -> string -> string -> (Entity_id.t -> 'a -> 'b -> unit) -> unit
val iter3 : World.t -> string -> string -> string -> (Entity_id.t -> 'a -> 'b -> 'c -> unit) -> unit
val iter4 : World.t -> string -> string -> string -> string -> (Entity_id.t -> 'a -> 'b -> 'c -> 'd -> unit) -> unit
```

These iterate only over alive entities with the requested component sets.

### 2.3 Default Stack Aliases

For most projects, the default stack provides:
- `World`: `Eon_ecs.World`
- `System`: `Eon_ecs.System.Default`
- `Pipeline`: `Eon_ecs.Pipeline.Default`
- `Progress`: `Eon_ecs.Progress.Default`
- `Loop`: `Eon_ecs.Loop.Default`
- `Signals`, `Events`, `Commands`: Direct access to buses

## 3. Eon Engine: Current State

### 3.1 Architecture Overview

The `eon_engine` package provides a **higher-level, typed component registration API** on top of Eon ECS. It abstracts away manual component ID management while maintaining full compatibility with the underlying ECS.

**Key Design Decision**: Component descriptors use phantom types for compile-time safety while remaining simple strings internally.

### 3.2 Component Registration System

#### 3.2.1 Module-Based Components

Components are defined as OCaml modules conforming to the `Component.S` signature:

```ocaml
module type S = sig
  type t
  val component : t Component_descriptor.t
  val name : string
end
```

#### 3.2.2 Component Descriptor

The `Component_descriptor` module provides:

```ocaml
type 'a t = string  (* Phantom type for type safety *)
type registration_result = Registered | Already_registered

val component : string -> 'a t
val register : Eon_ecs.World.t -> 'a t -> registration_result
val is_registered : Eon_ecs.World.t -> 'a t -> bool
val name : 'a t -> string
```

**Key Features**:
- Automatic ID generation using OCaml 5 `Atomic` features
- Idempotent registration (safe to call multiple times)
- Phantom type parameter ensures type safety when adding/getting components

#### 3.2.3 Built-in Components

Eon Engine includes 9 built-in components:

**Core Components**:
- `Position`: 2D position (x, y)
- `Velocity`: 2D velocity (vx, vy)
- `Rotation`: Angle in radians
- `Scale`: 2D scale (sx, sy)

**Rendering Components**:
- `Sprite`: Sprite rendering data
- `Animation`: Sprite animation data
- `Camera`: Camera configuration

**Gameplay Components**:
- `Collider`: Collision detection data
- `Tag`: Generic tag/marker component

### 3.3 API Structure

**Public API** (`eon_engine/eon_engine.mli`) — key modules:
```ocaml
module World      = World       (* Eon_engine.World.t, not Eon_ecs.World.t *)
module Components = Components
module Query      = Query       (* Query.Make(Sparse_set_backend.Default) *)
module View       = View
(* ... eon_ecs re-exports: Entity_id, Clock, Progress, Loop, ... *)
```

**Component Registration Flow**:
1. Create world: `let world = Eon_engine.World.create ()`
2. Register all built-in components: `Eon_engine.Components.Engine_components.register_all world`
3. Add to entities: `Eon_engine.World.add_component world entity Position.component {x=0.;y=0.}`
4. Query: `Query.from world |> Query.having_all [Position.name; Velocity.name] |> Query.iter (fun view -> ...)`

### 3.4 Re-export Convention — Single Import Point

**`Eon_engine` is the single import for all game code.** Game code should never
need to open or reference `Eon_ecs` directly. Every `Eon_ecs` module is either
owned and replaced by an engine version, or re-exported through `Eon_engine`
under the same name. The long-term goal is that `Eon_ecs` is an invisible
implementation detail — no game code ever writes `open Eon_ecs` or
`Eon_ecs.Foo`.

```ocaml
(* eon_engine.mli — re-exports of Eon_ecs modules with no engine equivalent *)
module Entity_id         = Eon_ecs.Entity_id
module Clock             = Eon_ecs.Clock
module Progress          = Eon_ecs.Progress
module Loop              = Eon_ecs.Loop
module Dependency_graph  = Eon_ecs.Dependency_graph
(* ... all remaining Eon_ecs public modules without an engine wrapper *)
```

**Why:** When `Eon_engine` wraps an `Eon_ecs` module with its own implementation
(e.g. `World` wrapping `Eon_ecs.World`), the re-export changes from
`= Eon_ecs.X` to the engine's wrapper. Game code that only ever imports
`Eon_engine` recompiles without any source changes.

**What is NOT re-exported:** Modules that `Eon_engine` wraps and extends —
`World`, `System`, `Pipeline`, `Query`, `Component`, `Bus`, `Single_bus`,
`Double_bus`. These have engine-specific wrappers that build upon the `Eon_ecs`
originals. In particular, `Single_bus` and `Double_bus` are standalone
engine-owned implementations with a `Mutex` on `emit` (see
[parallel_pipeline_execution.md §8](parallel_pipeline_execution.md));
the `eon_ecs` originals remain the no-Mutex sequential implementations used
internally by the core library and are left completely untouched.

**The rule:** If game code would otherwise write `Eon_ecs.X`, it belongs in
the re-export list. If `Eon_engine` has its own `X`, it does not.

## 4. Implemented Features (ecs-016 through ecs-020)

The following were delivered in prior tasks and are now part of the engine:

- **Query backend abstraction** (`Query_backend.S`, `Sparse_set_backend`) — ecs-016.
  `Query_backend.S` exposes only `iter_entities` + `count`; value extraction is
  via `View.get`, not per-arity callbacks. Archetype_backend and Fallback functor
  were dropped as premature.
- **Query builder** (`Query.Make`) — ecs-016. Single `iter` + `View` terminator
  replaces `iter1..iter4`. See [query_view_design.md](query_view_design.md).
- **World wrapper** (`World`, `World.S`) — ecs-016/017. Per-world `Id_counter`
  (OCaml 5 atomic record field); `to_raw` exposed as extension API.
- **Component groups** (`Components.register_all`) — ecs-018.
- **Data/service plane** (`World.add_data`, `World.add_service`, etc.) — ecs-019.
- **`iter_entities` in `eon_ecs`** + `Query.count` contract fix + `View` — ecs-020.

## 4.1 Parallel Pipeline (ecs-021, ecs-022, ecs-023/025/026)

The parallel execution layer described here is **implemented**. See
[parallel_pipeline_execution.md](parallel_pipeline_execution.md) for the full
spec. The engine **builds upon** `eon_ecs` — wraps core modules rather than
replacing them. Summary of what shipped:

- `Eon_ecs.Dependency_graph` — extracted topo-sort primitive (the **only** `eon_ecs` change)
- `Eon_engine.Bus` / `Single_bus` / `Double_bus` — standalone mutex-aware buses
- `Eon_engine.World` — `'perm t` phantom types (`ro`/`rw`) live directly on `World.t`, not a separate wrapper module (ecs-023 folded the earlier standalone `World_cap` into `World` itself)
- `Eon_engine.Executor` — threading-substrate seam; both `Sequential` (default) and `Domain_pool` (parallel, OCaml 5 domains) are implemented
- `Eon_engine.System.Make(Core_system)` — wraps any `Eon_ecs.System.S` with `World.ro`/`World.rw` (functor; `Default = Make(Eon_ecs.System.Default)`)
- `Eon_engine.Pipeline.Make(System)(Executor)` — parallel dispatch via Executor, reuses `Eon_ecs.Dependency_graph`; output satisfies `Eon_ecs.Pipeline.S`
- `Eon_engine.Loop_buses` — `BUSES` module closed over `Buses.Default.*` instances at module init; `collect`/`drain` are `unit -> unit` (no world argument, no service lookup)
- `Eon_engine.System.Parallel_def` / `Exclusive_def` — modular explicit module signatures encoding dispatch kind structurally via `World.ro`/`World.rw` (ecs-025); `make_parallel`/`make_exclusive` convenience functions usable flat in pipeline builders

No changes to `Eon_ecs.System.S`, `Eon_ecs.Pipeline.S`, `Eon_ecs.Progress`, or
`Eon_ecs.Loop`. `Eon_ecs.Progress.Make(Eon_engine.Pipeline.Default)` works
directly — no adapter needed. The engine demonstrates the extension pattern:
embed the core type, delegate to it, add capabilities on top.

## 5. Implementation Notes

### 5.1 Current Files

**eon_engine/**:
- `eon_engine.mli`, `eon_engine.ml`: Public API
- `world.mli`, `world.ml`: `World.S` signature + concrete `'perm World.t` module (capability model, `ro`/`rw`, folded in from the earlier standalone `World_cap`)
- `query_backend.mli`: `Query_backend.S` signature
- `query.mli`, `query.ml`: `Query.Make` builder functor
- `view.mli`, `view.ml`: `View.t` typed cursor for component reads
- `sparse_set_backend.mli`, `sparse_set_backend.ml`: Default query backend
- `bus.mli`, `bus.ml`: `Bus.S` signature
- `single_bus.mli`, `single_bus.ml`: Mutex-aware same-frame bus
- `double_bus.mli`, `double_bus.ml`: Mutex-aware next-frame bus
- `executor.mli`, `executor.ml`: `Executor.S` + `Sequential` + `Domain_pool`
- `system.mli`, `system.ml`: `System` reactive type
- `pipeline.mli`, `pipeline.ml`: `Pipeline.Make` functor
- `components.mli`, `components.ml`: Component registration API
- `component.mli`, `component.ml`: `Component.S` module signature
- `component_descriptor.mli`, `component_descriptor.ml`: Descriptor implementation
- `components/*.ml`, `components/*.mli`: Built-in component implementations

This list covers the parallel-pipeline-era files only (ecs-021/022/023 and
the capability merge); `eon_engine/` has grown substantially since with the
audio, input, transform, math/collision, resource/service, and prefab
subsystems — see their own `docs/design/*.md` entries in
[index.md](index.md) rather than expecting this section to be a complete
file manifest.

### 5.2 Build Configuration

```dune
(library
 (name eon_engine)
 (public_name eon-engine)
 (libraries eon-ecs))
```

The engine depends only on `eon-ecs`, maintaining a clean separation of concerns.

### 5.3 Testing Strategy

- Unit tests for component registration
- Integration tests with `Eon_ecs.World`
- Benchmark comparisons between query backends
- Property-based testing for query results

## 6. Rendering Layer

The rendering layer is designed as a separate component with backend autonomy. The engine and ECS core have no say in how rendering is performed - only the backend decides rendering order, shader usage, and techniques.

**Key Components**:
- **RenderGraph**: Backend-agnostic representation of renderable entities
- **RenderPipeline**: Collects entities into a render graph (similar to ECS Pipeline)
- **RenderingBackend**: Minimal interface with backend autonomy

**Design Principles**:
- Backend decides everything about rendering (order, shaders, techniques)
- Engine only provides data; backend decides how to use it
- Minimal backend interface (ideally just `render` function)
- Pluggable backends via compile-time functor application

See `docs/design/rendering_layer_design.md` for the complete rendering layer design.

## 7. Conclusion

Eon Engine provides a typed, ergonomic layer on top of the stable Eon ECS core: typed component registration, a query builder with `View`-based reads, a `World` wrapper with per-world id allocation, data/service plane, and phantom `ro`/`rw` capability types, and (ecs-021) a parallel pipeline with compile-time read/write safety.

The design maintains the core Eon principles of minimalism, extensibility, purity, and determinism while providing developer-friendly abstractions for common game development patterns.

# Eon Engine Design Document

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

Eon Engine includes 16 built-in components:

**Core Components**:
- `Position`: 2D position (x, y)
- `Velocity`: 2D velocity (vx, vy)
- `Acceleration`: 2D acceleration (ax, ay)
- `Rotation`: Angle in radians
- `Scale`: 2D scale (sx, sy)

**Resource Components**:
- `Health`: Health points
- `Mana`: Magic/energy resource

**Rendering Components**:
- `Sprite`: Sprite rendering data
- `Animation`: Sprite animation data
- `Camera`: Camera configuration

**Gameplay Components**:
- `Collider`: Collision detection data
- `Tag`: Generic tag/marker component
- `Lifetime`: Entity lifetime management
- `Input`: Input state and actions

### 3.3 API Structure

**Public API** (`eon_engine/eon_engine.mli`):
```ocaml
module Components = Components

val is_registered : Eon_ecs.World.t -> 'a Components.t -> bool
val component : string -> 'a Components.t
val register : Eon_ecs.World.t -> 'a Components.t -> Components.registration_result
```

**Component Registration Flow**:
1. Create component descriptor: `let pos = Engine.component "Position"`
2. Register with world: `Engine.register world pos`
3. Use with entities: `World.add_component world entity ~name:"Position" data`

### 3.4 Current Limitations

1. **No query builder abstraction**: Direct use of `Eon_ecs.Query` functions
2. **No backend abstraction**: Tight coupling with `Eon_ecs.World.t`
3. **No World wrapper**: Users work directly with `Eon_ecs.World`
4. **No component groups**: Manual registration of each component
5. **No entity factory patterns**: Manual entity creation and component addition

## 4. Future Features Planning

### 4.1 Next Tasks (ecs-016, ecs-017)

#### 4.1.1 Query Builder and Backend Abstraction (ecs-016)

**Goal**: Provide a typed query builder API with pluggable backends.

**Design**:
```ocaml
module type Query_backend.S = sig
  type world
  val iter1 : world -> includes:string list -> excludes:string list ->
              (Entity_id.t -> 'a -> unit) -> unit
  val iter2 : world -> includes:string list -> excludes:string list ->
              (Entity_id.t -> 'a -> 'b -> unit) -> unit
  (* ... iter3, iter4, count ... *)
end
```

**Backend Implementations**:
- `Sparse_set_backend`: Default backend, delegates to `Eon_ecs.Query`
- `Archetype_backend`: Acceleration cache using archetype index
- `Fallback`: Composable fallback between backends

**Query Builder API**:
```ocaml
module Make(B : Query_backend.S) : sig
  type query
  val from : B.world -> query
  val with_component : string -> query -> query
  val having : string -> query -> query  (* Presence check only *)
  val not_having : string -> query -> query
  val iter1 : (Entity_id.t -> 'a -> unit) -> query -> unit
  (* ... iter2, iter3, iter4, count ... *)
end
```

**User Wiring** (compile-time):
```ocaml
module Query = Eon_engine.Query.Make(Eon_engine.Sparse_set_backend)
```

#### 4.1.2 World Wrapper (ecs-017)

**Goal**: Wrap `Eon_ecs.World` in `Eon_engine.World` with higher-level component registration.

**Design**:
- Thin wrapper that forwards calls to `Eon_ecs.World`
- Integrates with automatic component ID generation
- Provides convenience methods for entity creation with components

**API**:
```ocaml
module World : sig
  type t = Eon_ecs.World.t

  val create : unit -> t
  val create_entity : t -> Entity_id.t

  (* Higher-level component operations *)
  val add_component : t -> Entity_id.t -> 'a Components.t -> 'a -> unit
  val set_component : t -> Entity_id.t -> 'a Components.t -> 'a -> unit
  val get_component : t -> Entity_id.t -> 'a Components.t -> 'a option
  val remove_component : t -> Entity_id.t -> 'a Components.t -> unit

  (* Forward to Eon_ecs.World *)
  val register_component : t -> name:string -> id:int -> unit
  val find_component : t -> name:string -> int option
  (* ... other operations ... *)
end
```

### 4.2 Future Roadmap

#### Phase 1: Query System (ecs-016)
- [ ] Implement `Query_backend.S` signature
- [ ] Implement `Sparse_set_backend`
- [ ] Implement `Archetype_backend`
- [ ] Implement `Query_backend_fallback`
- [ ] Implement `Query.Make` functor
- [ ] Update public API exports

#### Phase 2: World Wrapper (ecs-017)
- [ ] Create `eon_engine/world.mli` and `world.ml`
- [ ] Implement wrapper with automatic component ID integration
- [ ] Update `eon_engine.mli` to export `World` module
- [ ] Add convenience methods for entity creation

#### Phase 3: Component Groups (ecs-018)
- [ ] Define component group patterns
- [ ] Provide `register_all` helper for groups
- [ ] Document composition patterns

#### Phase 4: Entity Factory (ecs-019)
- [ ] Entity factory pattern for creating entities with predefined components
- [ ] Template-based entity creation
- [ ] Prefab system

#### Phase 5: System Integration (ecs-020)
- [ ] System registration with component dependencies
- [ ] Automatic system ordering based on component access
- [ ] Reactive system integration with query builder

#### Phase 6: Rendering Layer (ecs-021 to ecs-024)
- [ ] Render Graph - Backend-agnostic representation of renderable entities
- [ ] Rendering Backend - Minimal interface with backend autonomy
- [ ] Render Pipeline - Collects entities into render graph (similar to ECS Pipeline)
- [ ] Backend Implementations - Reference backends and documentation

See `docs/design/rendering_layer_design.md` for detailed rendering layer design.

### 4.3 Design Goals for Future Features

**Type Safety**
- All component operations remain type-safe via phantom types
- Query builder enforces arity matching at compile time
- Backend selection is compile-time configurable

**Performance**
- Sparse set backend provides optimal iteration performance
- Archetype backend provides acceleration for large worlds
- Fallback mechanism allows gradual migration

**Composability**
- Backends can be composed via functors
- Component groups can be extended
- Systems can be modularly composed

**Determinism**
- Query results are deterministic
- Backend selection is explicit and compile-time
- No hidden fallbacks or magic

## 5. Implementation Notes

### 5.1 Current Files

**eon_engine/**:
- `eon_engine.mli`, `eon_engine.ml`: Public API
- `components.mli`, `components.ml`: Component registration API
- `component.mli`, `component.ml`: Component module signature
- `component_descriptor.mli`, `component_descriptor.ml`: Descriptor implementation
- `components/*.ml`, `components/*.mli`: Built-in component implementations

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

Eon Engine provides a typed, ergonomic component registration API on top of the stable Eon ECS core. The current implementation establishes the foundation for component registration, with planned extensions for query building, world wrapping, rendering layer, and higher-level gameplay features.

The design maintains the core Eon principles of minimalism, extensibility, purity, and determinism while providing developer-friendly abstractions for common game development patterns.

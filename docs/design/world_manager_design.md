# World Manager Design

## Status

**SUPERSEDED.** No dedicated `Worlds` module will be built. The developer holds world values directly and composes them with `Namespace.S` for cross-world references. Multi-world topology is the developer's responsibility — consistent with the no-central-managers philosophy. This document is retained as historical context for why that decision was made.

## 1. The Problem

The per-world namespace map (see `data_service_plane_namespacing.md`) is sufficient for static topologies — wire everything up at startup, never change it. Dynamic topologies expose gaps:

- **Dangling references**: if a world is destroyed, any other world holding it in its namespace map still has a live reference to a dead simulation. There is no mechanism to detect or clean this up.
- **Transitions**: swapping `level_1` out for `level_2` requires manually rewiring every namespace reference that pointed at the old world. There is no atomic "swap" operation.
- **Enumeration**: there is no central place to ask "what worlds currently exist?" or "which worlds are connected to this one?"
- **Named worlds**: worlds are currently anonymous OCaml values. Dynamic systems (level loaders, debug tools, editors) need to refer to worlds by name.

The `Worlds` module is the natural owner of these concerns.

## 2. Responsibilities

`Worlds` would own:

- A registry of named worlds (`string -> World.t`)
- The namespace topology (which world is attached to which namespace on which world)
- Lifecycle operations: `create_world`, `destroy_world` with automatic cleanup
- Transition operations: rewire namespace references atomically

## 3. Open Design Questions

### 3.1 Ownership model

**Decided: the manager is a layer on top.**

Worlds keep their own namespace maps. The manager manipulates them from the outside — creating worlds, registering them by name, wiring their namespace maps, and scrubbing references on destroy. Worlds without a manager work exactly as designed; the manager is opt-in.

### 3.2 Reverse index for cleanup

Without an index, `destroy_world` must scan every registered world and every namespace entry to find stale references — O(W × N) where W is the number of worlds and N is the average namespace entries per world.

The manager maintains a **reverse index** as an internal acceleration structure: a sparse set keyed by integer world ID, where each slot holds the list of `(referencing_world_id, ns_string)` pairs that point at that world. The world's namespace map remains the source of truth; the index is derived from it.

```
index[target_world_id] → [(referencing_id, ns_string); ...]
```

- `attach_ns` through the manager: update the world's namespace map and append to `index[target.id]`
- `destroy_world`: look up `index[world.id]` in O(1), iterate only the worlds that reference it, remove stale entries, clean up the index slot

This reduces cleanup from O(W × N) to O(R) where R is the number of back-references to the destroyed world — typically very small.

**Caveat**: the index only covers namespace wiring that goes through the manager. A direct `attach_ns` call that bypasses the manager is not reflected in the index and will not be cleaned up on destroy. This is intentional — if you use the manager for namespace wiring you get safe cleanup; if you bypass it you are responsible. The two modes do not silently interfere.

### 3.3 Naming and identity

Should worlds have names assigned at creation time, or should names be registered separately? Options:

- `Worlds.create_world worlds "level_1"` — manager assigns the name at creation
- `Worlds.register worlds "level_1" world` — world exists first, name registered separately
- Both — creation through `Worlds` is the common path, manual registration is the escape hatch

### 3.4 Transition semantics

A level transition typically means: unload world A, load world B, rewire all namespaces that pointed at A to now point at B. Questions:

- Is the transition atomic from the perspective of other worlds, or can there be a frame where neither A nor B is attached?
- Does the old world get destroyed immediately or deferred (to allow fade-out, asset unloading, etc.)?
- Who is responsible for transferring state from the old world to the new one?

### 3.5 Lifecycle hooks

Should the manager support hooks on world events — `on_create`, `on_destroy`, `on_transition`? This enables asset loaders, audio engines, and other services to react to world lifecycle without polling. Risk: adds complexity and couples the manager to the service layer.

### 3.6 Serialization boundary

Serialization (save/restore world state) is explicitly out of scope for the WorldManager. It is a separate, harder problem that involves component layout, entity IDs, and data/service contents. It warrants its own design document. The WorldManager should be designed so that serialization can be built on top of it without requiring changes to the manager itself — topology metadata (world names, namespace wiring) is part of what serialization needs to capture.

## 4. Relationship to App.Make

When `App.Make` is eventually introduced (see `data_service_plane_namespacing.md` section 10), the `WorldManager` is a natural component of the application context it provides. The global world, the primary simulation world, and the namespace wiring between them would all be set up by `App.Make` using the manager internally. Whether the manager is exposed directly in the `App` module's public API or kept internal is an open question.

## 5. Future: World Execution Ordering

The namespace graph is a directed graph — worlds as nodes, namespace references as edges. `Pipeline` in `eon_ecs` operates on the same structure: phases as nodes, dependencies as edges, topological sort determines execution order. The structural parallel is exact.

Once multiple worlds coexist, some need to tick before others. The insight to preserve is: **the namespace graph already contains the dependency information** — a world that reads from another via a namespace implicitly depends on that world having ticked first. A world execution pipeline would make that implicit dependency explicit and enforce it automatically.

The two pipelines compose naturally:

```
World Pipeline (execution order across worlds)
  └── World A  →  Internal System Pipeline (execution order within a world)
  └── World B  →  Internal System Pipeline
  └── World C  →  Internal System Pipeline
```

Each world node in the world pipeline has its own internal system pipeline. Two levels of the same abstraction, each operating on the graph it owns.

### When world separation justifies itself

A single world with well-ordered phases handles most games cleanly. Multi-world separation earns its complexity only when worlds need **different operational characteristics** that phases cannot express:

**Independent tick rates** — physics typically runs at a fixed 120Hz for stability, gameplay at variable rate, rendering at display rate. With phases in one world this requires complex `Progress` mode switching per phase. With separate worlds each has its own `Progress` configuration and ticks independently.

**Independent pause and resume** — slow-motion in an action game means physics and character animation run at 20% speed while the UI and particle effects continue at full speed. With phases this requires conditional execution logic in every affected system. With separate worlds the slow-motion world simply receives a scaled `dt`; the UI world is unaffected.

**Hot-swapping** — the physics world can be swapped for a replay world, a simplified cutscene world, or a different backend without touching anything else. In a single world that is a full rebuild.

**Server/client split** — on a server there is no render world at all. On a client there may be a lightweight local world for visual effects only, with authoritative simulation state arriving from a server world attached via namespace. Worlds as units of deployment make this architecture natural.

**Parallelism** — worlds with no namespace dependency between them can tick concurrently. Phases in a single world are strictly sequential.

For a straightforward single-player game with one tick rate and no time manipulation, a single world with a single pipeline is simpler and exactly right. The multi-world pattern is not a default — it is a tool for the cases above.

This is not a near-term design task. The right time is after `Worlds` is stable and real multi-world execution patterns reveal what ordering guarantees are actually needed.

## 6. What to Build First

Before designing the WorldManager in full, the following should be in place and battle-tested:

- Namespacing implementation (data/service plane `~ns` API)
- At least one multi-world game pattern working end-to-end
- A concrete example of a level transition that requires namespace rewiring

The real shape of the API will be much clearer after that experience.

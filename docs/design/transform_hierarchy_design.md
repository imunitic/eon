# Transform Hierarchy Design — `eon_engine`

## Status

**DRAFT** — decisions captured, ready for task creation.

---

## 1. Motivation

A flat ECS world has no inherent notion of spatial relationships between
entities. A weapon attached to a character, a wheel fixed to a car body, a
UI label anchored to a panel — all of these require one entity's position in
the world to be derived from another's. Without hierarchy support, game code
must manually recompute and synchronise positions across all dependent
entities every frame. This is error-prone and doesn't scale.

The transform hierarchy solves this by maintaining two representations of
every entity's spatial state:

- **Local transform** — position, rotation, and scale relative to the parent
  (or world origin if the entity has no parent). This is what game code
  writes.
- **World transform** — the fully computed position in world space, derived
  by composing local transforms up the hierarchy. This is what rendering,
  physics sync, and spatial queries read.

The engine maintains consistency between the two. Game code never manually
propagates parent transforms to children.

---

## 2. Scope

This document covers the transform hierarchy as an `eon_engine` feature:

- The four components that express and cache the hierarchy
- The `Transform_system` that maintains world transforms top-down
- The `Reparent` command for safe hierarchy mutations
- Phase placement in the pipeline
- What stays in game layer

Math types (`Vec2`, `Transform2D`) are available in `Eon_engine.Math`
(shipped in ecs-030).

---

## 3. Component Design

Four components, all defined and registered by `eon_engine`. `Local_transform`
and `World_transform` replace the existing flat `Position`, `Rotation`, and
`Scale` components — those are removed as part of this task. `Velocity` is
kept as-is; it is not a spatial transform.

### 3.1 Local_transform

Position, rotation, and scale relative to the parent entity. If the entity
has no `Parent` component, this is relative to world origin.

```ocaml
type t = {
  position : Math.Vec2.t;
  rotation : float;          (* radians *)
  scale    : Math.Vec2.t;
}
```

Written by game systems (movement, animation, physics sync). The only
component in the hierarchy that game code directly mutates. Access pattern:

```ocaml
World.set_component world entity Local_transform.component
  { position = Math.Vec2.zero; rotation = 0.; scale = Math.Vec2.one }
```

### 3.2 World_transform

The computed world-space transform. Derived each frame by `Transform_system` —
game code must treat this as read-only.

```ocaml
type t = {
  position : Math.Vec2.t;
  rotation : float;
  scale    : Math.Vec2.t;
}
```

For root entities (no parent): `World_transform = Local_transform`.
For child entities: `World_transform = parent.World_transform ∘ Local_transform`.

Rendering and spatial queries read this. Physics sync writes `Local_transform`
and reads `World_transform`.

Kept as a separate component rather than a field on `Local_transform` — the
read-only contract is explicit and systems can query only what they need.

### 3.3 Parent

A reference to the parent entity. Absence means the entity is a root.

```ocaml
type t = { entity : Entity_id.t }
```

Game code does not set this directly mid-simulation — hierarchy mutations
go through the `Reparent` command (§5) to keep `Children` consistent. May be
set directly at world setup time before the loop starts.

### 3.4 Children

An engine-maintained cache of direct child entity IDs. Updated by
`Transform_system` when processing `Reparent` commands. Game code reads but
does not write this component.

```ocaml
type t = { entities : Entity_id.t list }
```

Without this cache, finding children requires scanning all `Parent` components
— O(n) per entity, O(n²) total. With it, DFS traversal is O(n) across the
whole hierarchy. `Entity_id.t list` is sufficient for typical game hierarchies
(shallow, low fan-out); revisit if profiling shows pressure here.

---

## 4. Transform System

A single exclusive system. Exclusive because it writes `World_transform` on
every entity that has a `Local_transform`. Hierarchy mutations (`Parent`,
`Children`) are handled in `on_command`, not in `update`.

### 4.1 Why not Query.iter

The standard `Query.iter` pattern has no guaranteed traversal order. Transform
propagation requires parents to be processed before children.
`Transform_system` owns its traversal — it uses the query API only to find
entry points (root entities), then drives the rest via `Children`.

### 4.2 Lifecycle split

```
on_command (Reparent) — drain phase, sequential, rw
  → mutate Parent and Children components to reflect the new hierarchy

update (exclusive) — tick phase, rw
  → DFS propagation: walk the now-consistent hierarchy, write World_transform
```

By the time `update` runs the hierarchy is already stable. Reparent commands
emitted during frame N's tick are processed during frame N's drain; frame N+1's
update sees the correct tree. One frame of latency on reparenting — correct
and expected.

### 4.3 Update algorithm

```
1. Find all root entities: have Local_transform, no Parent component
2. For each root — DFS:
     a. world_transform(root) = local_transform(root)
     b. for each child in children(root):
          world_transform(child) = world_transform(parent) ∘ local_transform(child)
          recurse into child's children
```

DFS naturally gives parent-before-child order without a sorting step.
`World.get_component` on a known `Entity_id.t` handles per-entity access
during traversal.

### 4.4 Transform composition

Parent scale applies to the child's local position offset before rotation:

```ocaml
let compose (parent : World_transform.t) (child : Local_transform.t) : World_transform.t = {
  position = Math.Vec2.add parent.position
               (Math.Vec2.rotate
                 (Math.Vec2.mul parent.scale child.position)
                 parent.rotation);
  rotation = parent.rotation +. child.rotation;
  scale    = Math.Vec2.mul parent.scale child.scale;
}
```

Non-uniform parent scale (e.g. `scale = (2.0, 1.0)`) distorts child positions
— child offsets are scaled along each axis independently before rotation is
applied. This is correct mathematically but can produce unintuitive results
with non-uniform scale in a hierarchy. Document this behaviour; avoid
non-uniform scale on hierarchy parents unless the distortion is intentional.

Decomposed position/rotation/scale is the chosen representation for 2D.
Matrix representation is not needed unless shear or more complex projections
are required.

---

## 5. Reparent Command

Hierarchy mutations during simulation go through a command on the command
bus — not direct component writes. This keeps `Parent` and `Children`
consistent and makes hierarchy changes auditable.

```ocaml
type reparent = {
  entity     : Entity_id.t;
  new_parent : Entity_id.t option;  (* None = detach, entity becomes a root *)
}
```

`Transform_system` handles `Reparent` in its `on_command` handler — part of
the drain phase, sequential, always `rw`:

- Remove `entity` from old parent's `Children` (if it had one)
- Add `entity` to new parent's `Children` (if `new_parent` is `Some`)
- Update or remove `Parent` component on `entity`

### 5.1 Destroyed parent behaviour

When a parent entity is destroyed, its children are **detached** — they
become roots with their current `World_transform` promoted to `Local_transform`.
No cascade destruction; children survive with their last known world position.

This requires a hook at `World.destroy_entity` time. The mechanism: game code
emits a `Reparent { entity = child; new_parent = None }` for each child before
destroying the parent, or `Transform_system` subscribes to an entity-destroyed
event if the engine provides one. For v1, the responsibility falls on game
code — document clearly that destroying a parent without detaching children
first leaves stale `Parent` references.

---

## 6. Pipeline Placement

The `Transform_system` must run:

- **After** any system that writes `Local_transform` (physics sync, movement,
  animation)
- **Before** any system that reads `World_transform` (rendering, spatial
  audio, UI layout)

Suggested phase order:

```
Physics_sync_phase   — physics body positions → Local_transform
Transform_phase      — Transform_system: propagates world transforms
Rendering_phase      — reads World_transform for draw calls
```

Phase definition and placement is the **game developer's responsibility** —
consistent with how audio and input integrate via the loop seam. `eon_engine`
ships `Transform_system`; the developer registers it in the correct phase.

---

## 7. Migration from flat components

`Position`, `Rotation`, and `Scale` in `eon_engine/components/` are removed
by this task. Impact is limited to tests:

- `test_query.ml` — uses `Components.Position` and `Components.Velocity` as
  example components to exercise the query API. Replace `Position` with
  `Local_transform` (or a custom test component) and keep `Velocity` as-is.
- `test_components.ml` — registers and exercises the component list. Update
  to reflect the new set.

No engine internals outside `components/` reference these types. No game code
exists yet.

---

## 8. What Stays in Game Layer

The engine provides the hierarchy machinery. Game code provides the
domain-specific usage:

- **Movement systems** — write `Local_transform` to move entities
- **Physics sync** — rigidbody body position → `Local_transform` (before
  `Transform_phase`); `World_transform` → physics body for queries (after)
- **Rendering** — reads `World_transform` and `Sprite` to produce draw calls
- **Camera follow** — reads `World_transform` of the target entity, adjusts
  viewport
- **Spatial audio** — reads `World_transform` for stereo positioning of audio
  sources

Game code never calls the DFS traversal, never directly writes
`World_transform`, and never directly writes `Children`.

---

## 9. Deferred

- **Dirty tracking** — current design recomputes all world transforms every
  frame. A dirty flag on `Local_transform` + propagation through `Children`
  would skip unchanged subtrees. Not needed for v1; flag for profiling.
- **Entity-destroyed event** — a formal engine event for entity destruction
  would make the destroyed-parent case cleaner. Deferred; v1 relies on game
  code to detach before destroy.

---

## 10. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Replace flat components | Yes — remove `Position`, `Rotation`, `Scale` | No game code exists; `Local_transform` is a strict superset; avoids two spatial representations |
| Separate Local/World components | Yes | Read-only contract on `World_transform` is explicit; systems query only what they need |
| Children cache | Yes, engine-maintained | O(n) DFS vs O(n²) without it; game code reads only |
| Traversal strategy | DFS from roots | Natural parent-before-child order; no sort step |
| Hierarchy mutations | Via `Reparent` command, handled in `on_command` | Keeps `Parent` + `Children` consistent; processed during drain before next update |
| Transform_system exclusivity | Exclusive | Writes `World_transform` — no concurrent access |
| Phase placement | Game developer's responsibility | Engine ships the system; developer places it in the correct phase |
| Destroyed parent | Detach — children become roots | No invisible cascade destruction; children survive with last world position |
| Composition formula | Scale child offset, then rotate, then translate | Correct 2D composition; non-uniform scale distorts child offsets (document, don't prevent) |
| Math types | `Eon_engine.Math.Vec2` | Available since ecs-030; no new dependency |

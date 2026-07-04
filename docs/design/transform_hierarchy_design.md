# Transform Hierarchy Design — `eon_engine`

## Status

**DRAFT** — captured from architecture discussion. Needs refinement before
implementation task is created. Open questions marked throughout.

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

Math types (`Vec2`, `Transform2D`) are a prerequisite but are a separate
design concern — see open questions §8.

---

## 3. Component Design

Four components, all defined and registered by `eon_engine`:

### 3.1 Local_transform

Position, rotation, and scale relative to the parent entity. If the entity
has no `Parent` component, this is relative to world origin.

```ocaml
type t = {
  position : Vec2.t;
  rotation : float;    (* radians *)
  scale    : Vec2.t;
}
```

Written by game systems (movement, animation, physics sync). The only
component in the hierarchy that game code directly mutates.

### 3.2 World_transform

The computed world-space transform. Derived each frame by the
`Transform_system` — game code must treat this as read-only.

```ocaml
type t = {
  position : Vec2.t;
  rotation : float;
  scale    : Vec2.t;
}
```

For root entities (no parent): `World_transform = Local_transform`.
For child entities: `World_transform = parent.World_transform ∘ Local_transform`.

Rendering and spatial queries read this. Physics sync writes `Local_transform`
and reads `World_transform`.

> **Open question:** Should world transform be a separate component or a
> computed field on `Local_transform`? Separate components make the
> read-only contract explicit and let systems query just what they need.
> Combined avoids double storage. Separate is the current preference.

### 3.3 Parent

A reference to the parent entity. Set by game code when attaching an entity
to a hierarchy. Absence means the entity is a root.

```ocaml
type t = { entity : Entity_id.t }
```

Game code does not set this directly mid-simulation — hierarchy mutations
go through the `Reparent` command (§5) to keep `Children` consistent.

### 3.4 Children

An engine-maintained cache of direct child entity IDs. Updated by
`Transform_system` when processing `Reparent` commands. Game code reads
but does not write this component.

```ocaml
type t = { entities : Entity_id.t list }
```

Without this cache, finding children requires scanning all `Parent`
components — O(n) per entity, O(n²) total. With it, DFS traversal is O(n)
across the whole hierarchy.

> **Open question:** `Entity_id.t list` vs a more compact representation.
> For typical game hierarchies (shallow, low fan-out) a list is fine.
> Revisit if profiling shows pressure here.

---

## 4. Transform System

A single exclusive system. Exclusive because it writes `World_transform`
and mutates `Children` when processing reparent commands.

### 4.1 Why not Query.iter

The standard `Query.iter` pattern has no guaranteed traversal order.
Transform propagation requires parents to be processed before children.
`Transform_system` owns its traversal — it uses the query API only to find
entry points (root entities), then drives the rest via `Children`.

### 4.2 Update algorithm

Each frame:

```
1. Process all pending Reparent commands — update Parent and Children components
2. Find all root entities: have Local_transform, no Parent component
3. For each root — DFS:
     a. world_transform(root) = local_transform(root)
     b. for each child in children(root):
          world_transform(child) = world_transform(parent) ∘ local_transform(child)
          recurse into child's children
```

DFS naturally gives parent-before-child order without a sorting step.
`World.get_component` on a known `Entity_id.t` handles per-entity access
during traversal.

### 4.3 Transform composition

```ocaml
let compose parent child = {
  position = Vec2.add parent.position (Vec2.rotate child.position parent.rotation);
  rotation = parent.rotation +. child.rotation;
  scale    = Vec2.mul parent.scale child.scale;
}
```

> **Open question:** Matrix representation vs decomposed position/rotation/scale.
> Decomposed is more readable and sufficient for 2D. Matrices become relevant
> if shear or non-uniform scaling through hierarchy is needed. Start decomposed.

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

`Transform_system` drains `Reparent` commands at the start of its exclusive
update before the DFS pass:

- Remove `entity` from old parent's `Children` (if it had one)
- Add `entity` to new parent's `Children` (if `new_parent` is `Some`)
- Update or remove `Parent` component on `entity`

> **Open question:** What happens to children when a parent entity is
> destroyed? Options:
> a. Cascade destroy — children destroyed with the parent
> b. Detach — children become roots with their current world transform
>    promoted to local transform
> c. Reparent to grandparent — maintain relative position in hierarchy
>
> Option (b) is the safest default — no invisible mass destruction,
> children survive. Needs an explicit hook in `World.destroy_entity`.

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

> **Open question:** Should `eon_engine` define and register these phases,
> or leave phase definition entirely to the game developer? The audio and
> input systems don't define pipeline phases — they integrate via the loop
> seam. Transform is different because it's a mid-pipeline system, not a
> loop-level concern. Likely the game developer defines phases and places
> `Transform_system` in the right one explicitly.

---

## 7. What Stays in Game Layer

The engine provides the hierarchy machinery. Game code provides the
domain-specific usage:

- **Movement systems** — write `Local_transform` to move entities
- **Physics sync** — rigidbody body position → `Local_transform` (before
  `Transform_phase`); `World_transform` → physics body for queries (after)
- **Rendering** — reads `World_transform` and `Sprite` to produce draw calls
- **Camera follow** — reads `World_transform` of the target entity, adjusts
  viewport
- **Spatial audio** — reads `World_transform` for 3D/stereo positioning of
  audio sources

Game code never calls the DFS traversal, never directly writes
`World_transform`, and never directly writes `Children`.

---

## 8. Open Questions

In rough priority order:

1. **Math types prerequisite.** `Vec2` and `Transform2D` need to exist before
   this can be implemented. Are these in `eon_engine` or a separate package?
   What is the canonical Vec2 representation? Needs its own design task.

2. **Destroyed parent behaviour.** Cascade vs detach vs reparent-to-grandparent
   (§5 open question). Default recommendation is detach but needs decision.

3. **Dirty tracking.** Current design recomputes all world transforms every
   frame. For large hierarchies this is wasteful — most transforms don't
   change most frames. A dirty flag on `Local_transform` + propagation through
   `Children` would skip unchanged subtrees. Not needed for v1 but worth
   flagging for profiling.

4. **Non-uniform scale through hierarchy.** `Vec2` scale composes by
   multiplication. Non-uniform parent scale (e.g. `scale = (2.0, 1.0)`)
   distorts child positions in potentially unexpected ways. Document the
   behaviour, potentially warn against non-uniform scale in hierarchies.

5. **Phase placement ownership.** Whether `eon_engine` ships canonical phase
   names for transform, rendering, and physics sync (§6 open question).

6. **Matrix vs decomposed representation.** Current preference: decomposed
   position/rotation/scale (§4.3 open question). Revisit if shear is needed.

---

## 9. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Separate Local/World components | Yes | Read-only contract on World_transform is explicit; systems query only what they need |
| Children cache | Yes, engine-maintained | O(n) DFS vs O(n²) without it; game code reads only |
| Traversal strategy | DFS from roots | Natural parent-before-child order; no sort step |
| Hierarchy mutations | Via Reparent command | Keeps Parent + Children consistent; auditable |
| Transform_system exclusivity | Exclusive | Writes World_transform and Children — no concurrent access |
| Phase placement | Game developer's responsibility | Consistent with how audio and input integrate; engine ships the system, not the phases |

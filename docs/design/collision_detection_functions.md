# Collision Detection Functions Design — `eon_engine`

## Status

**IMPLEMENTED** (ecs-037).

---

## 1. Motivation

`Collider` (`eon_engine/components/collider.ml`) is data only — Eon ships no
built-in physics simulation. A developer who wants collision behaviour reads
`Collider` off entities and builds their own system. Today they get shape data
(`Circle | Box | Capsule`) but no way to test two shapes against each other
without hand-rolling the math.

This design adds that missing piece: a small set of shape-vs-shape collision
**detection** functions. They close the gap between "I have two colliders"
and "do they overlap, and if so, how do I push them apart" — without Eon
taking ownership of resolution, stepping, or a `Collision_system`.

---

## 2. Scope

**In scope:** Circle-Circle, Circle-Box, Box-Box detection with contact
information (normal + penetration depth) sufficient for simple resolution.

**Deferred:** Capsule pairs (`Capsule`-`Capsule`, `Capsule`-`Circle`,
`Capsule`-`Box`). `Collider.shape` already has a `Capsule` constructor for
forward compatibility, but no capsule test is implemented yet — see
[[project_collision_resolution_scope]] (circle+box only for now).

**Explicitly not in scope:**
- A `Collision_system` or any query/system that runs these functions over
  entities. Developers wire that themselves, same as the existing `Collider`
  philosophy.
- Continuous collision detection (swept shapes) — only discrete overlap
  tests at a single instant.
- Broad-phase / spatial partitioning (quadtree, grid). These functions are
  narrow-phase only; a developer supplies the pair to test.
- Resolution (impulse response, position correction). Detection returns a
  `Manifold.t`; what the developer does with it is their problem.
- Contact point, torque, angular response, mass, moment of inertia — any
  rotational or rigid-body collision response. Permanently out of scope, not
  just deferred. `normal` + `depth` support straight-line separation
  (arcade-style push-apart, trigger detection, simple non-rotating movement
  resolution), which covers most 2D games. A game that needs "hitting a box
  off-center spins it realistically" needs mass, moment of inertia, angular
  velocity, and a real constraint solver — i.e. it has already crossed into
  rigid-body simulation regardless of what this module provides. That's a
  physics engine's job (Box2D, Chipmunk2D), not this module's. Physics
  engines don't reuse the host engine's transform type either — they own
  their own body representation (position, angle, velocity, mass) and sync
  it into `Transform2D` each frame (read back for rendering, write for
  kinematic bodies); Eon's math/collision layer is not going to grow toward
  that one function at a time. If a game needs rigid bodies or gravity, the
  answer is "integrate a physics engine," not "extend `Manifold.t`."

---

## 3. Placement

These functions are **pure math, not component-aware**. They take
`Math.Circle.t` / `Math.Rect.t` (plus a position where the shape needs one)
and return overlap data — no `Collider.t`, no `Component_descriptor`, no
`World` in sight. That is what makes them usable outside the ECS entirely
(unit tests, other tools) and is consistent with the rest of `math.ml`:
`Rect.intersects` and `Circle.intersects` / `Circle.intersects_rect` already
live there and already do the boolean-only version of two of these three
pairs.

They belong in `eon_engine/math.ml` / `math.mli`, as an extension of the
existing `Circle` and `Rect` modules — not a new file, not a new component,
not a system. A developer maps their own `Collider.shape` + `Transform2D` to
`Math.Circle.t` / `Math.Rect.t` at the call site:

```ocaml
let shape_at (collider : Collider.t) (transform : Transform2D.t) =
  match collider.shape with
  | Collider.Circle r -> `Circle (Math.Circle.create transform.position r)
  | Collider.Box (w, h) ->
    `Rect (Math.Rect.create
             (transform.position.x -. w /. 2.)
             (transform.position.y -. h /. 2.)
             w h)
  | Collider.Capsule _ -> failwith "not yet supported"
```

That mapping function is the developer's own system code — Eon does not
provide it, matching how `collider.mli` already documents the integration
pattern.

---

## 4. API

New type: `Math.Manifold.t`, plus three new functions on `Circle` and `Rect`.

```ocaml
module Manifold : sig
  type t = {
    normal : Vec2.t;  (** Unit vector — points from the first shape toward the
                          second. Direction to push the second shape to
                          resolve the overlap. *)
    depth  : float;   (** Penetration depth along [normal]. Always >= 0. *)
  }
end

module Circle : sig
  (* ... existing ... *)

  val collide : t -> t -> Manifold.t option
  (** Circle-circle overlap test with contact data. [None] if disjoint.
      [normal] points from the first circle's center toward the second's. *)

  val collide_rect : t -> Rect.t -> Manifold.t option
  (** Circle-box overlap test with contact data. [None] if disjoint.
      [normal] points from the rect toward the circle (i.e. the direction
      that would push the circle out of the box). *)
end

module Rect : sig
  (* ... existing ... *)

  val collide : t -> t -> Manifold.t option
  (** Box-box (AABB) overlap test with contact data. [None] if disjoint.
      [normal] points from the first rect toward the second, along the axis
      of minimum penetration (standard AABB manifold — one of the four axis
      directions). *)
end
```

Notes:
- `Manifold.t` is a single shared type — same shape regardless of which pair
  produced it, so a developer's resolution code doesn't need to branch on
  which `collide*` function was called.
- `bool`-only tests (`intersects`, `intersects_rect`) stay as-is — cheaper
  when a developer only needs a yes/no answer (e.g. trigger volumes, culling)
  and doesn't need to resolve anything. `collide*` is the superset for when
  resolution data is needed.
- No `collide` for `Circle -> Rect -> Circle -> ...` in the other argument
  order — callers needing "box vs circle" flip the manifold's normal
  (`Vec2.neg`), same convention as `Circle.intersects_rect` already
  establishes the circle-first argument order.

---

## 5. Manifold math

**Circle-Circle** (`Circle.collide`):
```
d = b.center - a.center
dist = length d
overlap = a.radius + b.radius - dist
if overlap <= 0 then None
else
  normal = if dist > 0 then d / dist else Vec2.{x=1; y=0}  (* degenerate: same center *)
  Some { normal; depth = overlap }
```

**Circle-Box** (`Circle.collide_rect`):
Standard clamp-to-nearest-point approach:
```
closest = clamp circle.center to rect bounds (Rect.min, Rect.max)
d = circle.center - closest
dist = length d
if dist > circle.radius then None
else if dist > 0 then
  normal = d / dist  (* points from rect toward circle *)
  Some { normal; depth = circle.radius - dist }
else
  (* center is inside the box — fall back to push out along the
     shallowest penetration axis, same as Box-Box *)
  ...
```
The degenerate "center inside the box" case reuses the axis logic below.

**Box-Box** (`Rect.collide`):
Standard AABB minimum-translation-vector approach — compute overlap on both
axes, push out along whichever is smaller:
```
overlap_x = min(a.max.x, b.max.x) - max(a.min.x, b.min.x)
overlap_y = min(a.max.y, b.max.y) - max(a.min.y, b.min.y)
if overlap_x <= 0 || overlap_y <= 0 then None
else if overlap_x < overlap_y then
  normal = if a.center.x < b.center.x then {x=1; y=0} else {x=-1; y=0}
  Some { normal; depth = overlap_x }
else
  normal = if a.center.y < b.center.y then {x=0; y=1} else {x=0; y=-1}
  Some { normal; depth = overlap_y }
```

All three share the convention: **`normal` points from the first argument
toward the second**, and `depth >= 0`. This matches the existing
argument-order convention on `Circle.intersects_rect : Circle.t -> Rect.t ->
bool` (circle first).

---

## 6. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Location | `math.ml`, extending `Circle`/`Rect` | Pure geometry, no `Collider`/`Component_descriptor`/`World` dependency — usable standalone, consistent with existing `intersects*` |
| No `Collision_system` | Not built | `Collider` philosophy is data-only; developers already build their own systems per `collider.mli` |
| Shared `Manifold.t` | One type for all three pairs | Resolution code doesn't need to branch on which shape pair produced it |
| Capsule pairs | Deferred | Per [[project_collision_resolution_scope]] — not a near-term need |
| Argument order | Shape-vs-shape, first-to-second normal | Matches existing `Circle.intersects_rect` (circle-first) convention; no reverse-order variants — caller negates the normal instead |
| Keep `intersects`/`intersects_rect` | Unchanged, boolean-only | Cheaper path for trigger/cull checks that don't need resolution data |
| Broad-phase / CCD | Out of scope | Narrow-phase discrete tests only; spatial partitioning and swept shapes are separate concerns for a developer's own system |

---

## 7. Future Extension: Parametric Manifold (not adopted now)

**Decision:** `Manifold.t` stays a single, non-parametric shared type (§4).
This section records a considered alternative — a parametric hybrid — so the
option isn't rediscovered from scratch if some *other* pair-specific data
need shows up later (contact point / torque is not such a case — that's a
permanent non-goal per §2, not a pending one).

The idea: keep `normal`/`depth` shared across all pairs, but add a slot for
pair-specific data that starts empty and can gain a real type per-pair
without touching the other pairs or any generic resolution code.

```ocaml
module Manifold : sig
  type 'a t = {
    normal : Vec2.t;
    depth  : float;
    extra  : 'a;
  }
end
```

Every `collide*` function would return `unit Manifold.t` today (`extra = ()`):

```ocaml
val collide      : Circle.t -> Circle.t -> unit Manifold.t option
val collide_rect : Circle.t -> Rect.t   -> unit Manifold.t option
val collide      : Rect.t   -> Rect.t   -> unit Manifold.t option
```

Generic resolution code stays generic over the extra payload:

```ocaml
let push_out (m : _ Manifold.t) = Vec2.mul m.normal m.depth
```

If Box-Box later needs a contact point, only that one function's signature
changes — `normal`/`depth` access and `push_out` are untouched:

```ocaml
type box_extra = { point : Vec2.t }
val collide : Rect.t -> Rect.t -> box_extra Manifold.t option
```

`box_extra`/contact point is used here purely to illustrate the mechanism —
not a live candidate; torque and contact point are a permanent non-goal per
§2, not a pending one.

**Why not adopted now:** `extra = ()` on every pair is dead weight until a
pair actually diverges — adding the type parameter today buys nothing that
isn't already achievable by widening the plain shared type later (a
`Manifold.t` field addition is a mechanical, low-risk change with only three
call sites). Revisit only if some other, non-rotational pair-specific field
request comes in.

### 7.1 If all three pairs genuinely diverge: existential wrapper

The parametric type above has one sharp edge: the moment `extra` actually
differs per pair (e.g. `unit` for Circle-Circle, `box_extra` for Box-Box),
`unit Manifold.t` and `box_extra Manifold.t` become different types — you can
no longer put them in one `list` to resolve generically, which was the whole
reason for wanting a shared type in the first place.

The fix, if this ever happens, is an existential wrapper around the
parametric type:

```ocaml
type any_manifold = Any : 'a Manifold.t -> any_manifold
```

This erases only `'a` (the `extra` payload). `normal` and `depth` stay
concrete on every instantiation, so generic code needs just one shallow
pattern match to get back to them — no per-field unwrapping tax:

```ocaml
let push_out (m : _ Manifold.t) = Vec2.mul m.normal m.depth

let resolve_all (contacts : any_manifold list) =
  List.iter (fun (Any m) -> apply_push (push_out m)) contacts
```

This gives you both things at once: pair-specific `extra` data where it's
needed, and one homogeneous list of contacts for a generic resolution pass
— the pattern that motivated a shared type in §4 still holds even once the
pairs diverge.

**Limitation:** once a manifold is boxed as `any_manifold`, `extra`'s
concrete type is gone — you cannot read `m.extra.point` generically after
erasure. The pattern only works if pair-specific data is consumed
immediately, right after calling e.g. `Rect.collide`, while the concrete
`box_extra Manifold.t` is still in hand — and only the pair-agnostic fields
(`normal`, `depth`) need to survive into the generic, erased list. If a case
arises where the *erased* list itself needs to recover which concrete pair
produced an entry (to dispatch differently per pair during resolution), that
needs a correlating tag alongside the existential (a small GADT index) —
more machinery again, and only worth it if that specific need materializes.

**Still not adopted now** — this whole section (7 and 7.1) is a considered
alternative on record, not a decision. Nothing today has heterogeneous
`extra` data; revisit only if/when it does (for a non-rotational reason —
see §2 for why torque/contact point specifically will not be that reason).

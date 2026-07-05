# Math Types Design — `eon_engine`

## Status

**IMPLEMENTED** (ecs-030).

---

## 1. Motivation

A 2D engine needs a small, concrete set of math primitives. These are not a
variation point — there is no `Vec2.S` signature and no functor parameter.
Math types are concrete values; `Vec2.t` is embedded in component types like
`Local_transform` and must be a single known type across the engine.

All three types live in a single module:

```
eon_engine/math.ml
eon_engine/math.mli
```

Game code aliases what it needs:

```ocaml
open Eon_engine.Math

let pos = Vec2.add a b
let bounds = Rect.intersects r1 r2
```

---

## 2. Vec2

The fundamental 2D primitive. Used for position, velocity, direction, and
scale throughout the engine and game layer.

```ocaml
module Vec2 : sig
  type t = { x : float; y : float }

  (* construction *)
  val zero       : t
  val one        : t
  val create     : float -> float -> t

  (* arithmetic *)
  val add   : t -> t -> t
  val sub   : t -> t -> t
  val mul   : t -> float -> t      (* scalar multiply *)
  val div   : t -> float -> t      (* scalar divide *)
  val neg   : t -> t
  val mul_v : t -> t -> t          (* component-wise multiply — scale composition *)

  (* geometric *)
  val dot         : t -> t -> float
  val length      : t -> float
  val length_sq   : t -> float     (* avoids sqrt — use for comparisons *)
  val normalize   : t -> t
  val distance    : t -> t -> float
  val distance_sq : t -> t -> float
  val clamp       : t -> min:t -> max:t -> t  (* component-wise clamp *)
  val reflect     : t -> t -> t               (* reflect across surface normal *)
  val project     : t -> onto:t -> t          (* project onto vector *)

  (* rotation *)
  val perpendicular : t -> t        (* 90° CCW: {x = -v.y; y = v.x} *)
  val rotate        : t -> float -> t
  val angle         : t -> float
  val from_angle    : float -> t

  (* utils *)
  val lerp : t -> t -> float -> t
end
```

`t` is exposed as a record — game code reads `v.x` and `v.y` directly without
accessor noise. `mul_v` is the component-wise multiply needed for scale
composition in the transform hierarchy (`parent.scale * child.scale`).
`length_sq` and `distance_sq` skip the square root and should be preferred
for comparisons and culling.

---

## 3. Rect

Axis-aligned bounding box. Used for collision detection, spatial culling, and
UI layout.

```ocaml
module Rect : sig
  type t = { x : float; y : float; w : float; h : float }

  (* construction *)
  val create     : float -> float -> float -> float -> t  (* x y w h *)
  val of_min_max : Vec2.t -> Vec2.t -> t

  (* accessors *)
  val min    : t -> Vec2.t
  val max    : t -> Vec2.t
  val center : t -> Vec2.t

  (* queries *)
  val contains_point : t -> Vec2.t -> bool
  val intersects     : t -> t -> bool
  val intersection   : t -> t -> t option

  (* transform *)
  val translate : t -> Vec2.t -> t
  val expand    : t -> float -> t   (* uniform padding *)
  val scale     : t -> float -> t   (* scale position and dimensions around origin *)
  val merge     : t -> t -> t       (* union — for bounding box accumulation *)
end
```

`t` is exposed as a record for the same reason as `Vec2`. `merge` computes the
smallest rect containing both inputs — useful when building bounding boxes from
a set of points or child entities.

---

## 4. Transform2D

Decomposed 2D transform: position, rotation (radians), and scale. Used by the
transform hierarchy components (`Local_transform`, `World_transform`) and for
camera and rendering math.

Decomposed representation is preferred over a 2x3 matrix for 2D — it is more
readable, sufficient for all 2D use cases, and avoids the need for matrix
decomposition. Shear is not supported; non-uniform scale through a hierarchy is
documented as producing expected but potentially surprising distortion.

```ocaml
module Transform2D : sig
  type t = {
    position : Vec2.t;
    rotation : float;    (* radians *)
    scale    : Vec2.t;
  }

  (* construction *)
  val identity : t
  val create   : position:Vec2.t -> rotation:float -> scale:Vec2.t -> t

  (* composition — core hierarchy operation *)
  val compose : t -> t -> t
  (** [compose parent child] produces the world-space transform of [child]
      given its [parent]'s world transform (full TRS). Result:
        position = parent.position + rotate(child.position * parent.scale, parent.rotation)
        rotation = parent.rotation + child.rotation
        scale    = Vec2.mul_v parent.scale child.scale *)

  (* application *)
  val apply_point : t -> Vec2.t -> Vec2.t
  (** Transform a point from local space to world space. *)

  val inverse : t -> t
  (** Inverse transform — converts world space back to local space. *)

  (* accessors — direct field access preferred, these are for
     contexts where only one component is needed *)
  val position : t -> Vec2.t
  val rotation : t -> float
  val scale    : t -> Vec2.t

  (* utils *)
  val lerp_angle : float -> float -> float -> float
  (** Shortest-path interpolation between two angles — always takes the shorter
      arc, correctly handles the ±π boundary. *)

  val lerp : t -> t -> float -> t
  (** Linear interpolation using shortest-path rotation via [lerp_angle].
      Safe across the ±π boundary. Replaces the naive float lerp on rotation. *)
end
```

`compose` is the critical operation — it is called by `Transform_system` on
every entity in the hierarchy every frame. `apply_point` and `inverse` are
used for world↔local coordinate conversion (picking, camera, physics sync).
`lerp` uses `lerp_angle` for the rotation field so it always takes the shortest
arc; there is no naive float-lerp variant.

Full TRS `compose` formula (corrected from initial design):
```
position = parent.position + rotate(child.position * parent.scale, parent.rotation)
rotation = parent.rotation + child.rotation
scale    = Vec2.mul_v parent.scale child.scale
```
Non-uniform scale breaks the `apply_point (compose p c) pt = apply_point p (apply_point c pt)`
law — a known limitation shared by Unity, Godot, and Bevy.

---

## 5. Vec2i

Integer 2D vector for tile coordinates, grid indices, and EDN-loaded level data.

```ocaml
module Vec2i : sig
  type t = { x : int; y : int }

  val zero   : t
  val one    : t
  val create : int -> int -> t

  val add   : t -> t -> t
  val sub   : t -> t -> t
  val mul   : t -> int -> t
  val neg   : t -> t
  val mul_v : t -> t -> t

  val to_vec2       : t -> Vec2.t   (* exact, no precision loss *)
  val of_vec2_floor : Vec2.t -> t   (* world pos → tile the entity occupies *)
  val of_vec2_round : Vec2.t -> t   (* snap to nearest tile center *)
  val of_vec2_ceil  : Vec2.t -> t   (* extent / covering calculations *)
end
```

---

## 6. Circle

Circle shape for collision detection and radial spatial queries.

```ocaml
module Circle : sig
  type t = { center : Vec2.t; radius : float }

  val create         : Vec2.t -> float -> t
  val contains_point : t -> Vec2.t -> bool
  val intersects     : t -> t -> bool
  val intersects_rect : t -> Rect.t -> bool
end
```

Cheaper than `Rect` for radial checks (distance-squared vs AABB overlap).
Natural for explosion radii, aggro ranges, and pick-up areas.

---

## 7. What is Not Here

Deliberately excluded — add only when a system actually requires it:

| Type / function | Reason excluded |
|---|---|
| `Mat3` / `Mat4` | Renderer-internal concern; game code never touches matrices |
| `Vec3`, `Vec4`, `Quaternion` | 3D — out of scope |

`Color` is a rendering concern and lives in the rendering layer, not here.

---

## 8. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Single file | `math.ml` / `math.mli` | Three small modules; no need for separate files |
| No `Vec2.S` signature | Concrete only | `Vec2.t` is embedded in component types — substitution requires functors which are not worth it for math |
| Decomposed `Transform2D` | position / rotation / scale | Readable; sufficient for 2D; no matrix decomposition needed |
| Exposed record types | `type t = { x; y }` | Direct field access without accessor noise |
| `length_sq` / `distance_sq` | Included alongside `length` / `distance` | Skip sqrt for comparisons and culling — common hot path |
| Shear | Not supported | Non-uniform scale through hierarchy is documented; shear requires matrix representation |
| `Transform2D.lerp` | Uses `lerp_angle` for rotation | Naive float lerp on rotation goes the long way around ±π — the correct version is always safe and has negligible extra cost |
| `Transform2D.compose` | Full TRS | `position = parent.pos + rotate(child.pos * parent.scale, parent.rot)` — matches Unity/Godot/Bevy; simplified version (without scale on child offset) was a training-data artefact |

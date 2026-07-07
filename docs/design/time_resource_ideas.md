# Time Resource

## Status

**DRAFT** — decisions settled, ready for task creation and implementation.

---

## The One-Liner

`dt` stays as an explicit `update` parameter — documents time-awareness at
the signature level. `Time` exists as a resource for richer time data that
`dt` alone doesn't cover.

```ocaml
(* common case — dt is enough *)
let update world dt = ...

(* richer time needed — fetch the resource *)
let update world _dt =
  let time = Time.fetch world in
  if time.elapsed > 30.0 then ...
```

---

## Data

```ocaml
type t = {
  delta   : float;   (* seconds since last frame — same as the dt parameter *)
  elapsed : float;   (* total seconds since the loop started *)
  frame   : int;     (* frame counter, starts at 0 *)
}
```

`delta` mirrors `dt` — redundant but consistent. A system that fetches
`Time` gets everything in one place without also reading the parameter.

---

## Decisions

### `Time.delta` in fixed/hybrid mode

`Time.delta` is always the **real frame delta** — the `dt` passed to
`Progress.tick` from the loop. It does not reflect the fixed sub-step.

Fixed and hybrid systems that need the exact step duration use the `dt`
parameter already passed to `update`. `Time` is a frame-level resource,
not a per-tick resource. Writing it once per frame (before any dispatch)
is the only coherent option — writing it per fixed sub-tick would cause
`elapsed` and `frame` to advance multiple times per frame.

### Frame numbering

The first frame is **frame 0**. The resource is pre-initialised to
`{ delta = 0.; elapsed = 0.; frame = 0 }` during world setup. Each
`Progress.tick` writes the updated value before dispatch, so after the
first tick frame becomes 1. Systems always read the current frame's value.

### Resource as its own accumulator

No shadow state lives outside the resource. `elapsed` and `frame` are
accumulated by reading the previous value before each write:

```ocaml
let prev = try Time.fetch world with Not_found -> Time.zero in
Time.store world { delta = dt; elapsed = prev.elapsed +. dt; frame = prev.frame + 1 }
```

Pre-initialising the resource at world setup removes any "missing on first
frame" edge case and makes `Time.fetch` safe to call before the first tick:

```ocaml
Time.store world Time.zero
```

### Pause

The engine's pause contract is simple: pause = time stops. `Progress.tick`
still runs — buses collect and drain, systems execute — but `dt = 0.0` so
`elapsed` and `frame` do not advance.

`Eon_engine.Loop.run` gains a `~paused:(world -> bool)` predicate (defaults
to `fun _ -> false`). When it returns true the loop passes `~now:last_time`
to the internal `step`, making `dt = last_time - last_time = 0.0`. The real
clock value is always used as `last_time` for the next iteration, so there
is no time jump on unpause. `step` itself is unchanged. Pause state lives
in the world (a resource or marker component) — the predicate just reads it.

What games do with pause beyond that is their concern — keeping UI running,
ticking audio independently, splitting clocks — these are game-layer problems.
The engine has no opinion on them. Do not add fields to `Time.t` for these
use cases.

---

## Where Time Lives

`Time` is an `eon_engine` concern, not an `eon_ecs` primitive. `eon_ecs`
has no awareness of `Time.S` or any time resource.

### Module boundary

- `Time.S` and the concrete `Time` module live in `eon_engine`.
- `Eon_ecs.Progress` is untouched — it knows nothing about Time.
- `Eon_engine.Progress` wraps `Eon_ecs.Progress` and adds the Time write
  as a pre-tick step via `Make_with_time`.

### `Eon_engine.Progress.Make`

A pass-through alias — identical to `Eon_ecs.Progress.Make`. Engine-layer
users who don't need `Time` use this and never touch `eon_ecs` directly.

### `Eon_engine.Progress.Make_with_time`

```ocaml
(* eon_engine *)
module Progress = struct
  module Make_with_time
    (P : Eon_ecs.Pipeline.S)
    (T : Time.S)
  = struct
    module Base = Eon_ecs.Progress.Make(P)

    let tick t ~world ~dt =
      T.write world dt;          (* fetch-or-zero, increment, store — before any system runs *)
      Base.tick t ~world ~dt
  end
end
```

Whatever world `T.write` receives must satisfy `Eon_engine.World.S` with
`rw` capability — writing is a mutation and the type system enforces this.
The wrapper holds a world satisfying that constraint before dispatch, so
the call is natural.

### `Time.S` signature

`Time.S` is hand-written — not via `Resource.Make`. `Resource.Make` is for
resources that need only `fetch`/`store`; `Time` adds `zero` and `write` so
it writes its own `fetch` and `store` directly against `World.get_data` /
`World.set_data`.

```ocaml
module type S = sig
  type t = { delta : float; elapsed : float; frame : int }
  val fetch : [> World.ro] World.t -> t
  val store : World.rw World.t -> t -> unit
  val zero  : t
  val write : World.rw World.t -> float -> unit  (* fetch-or-zero, increment, store *)
end
```

`write` is the one entry point `Progress.Make_with_time` calls. `fetch`,
`store`, and `zero` are exposed for world setup and testing.

---

## Methods

`Time.t` is a plain record — data only, no behaviour. Helpers like
`Time.seconds_to_frames` or `Time.fps` can be added later if a real
consumer needs them. Do not add them speculatively.

---

## Not in Scope

- Helpers / computed fields on `Time.t` — add on demand.
- Any time tracking outside the `Time` resource — `Progress` and the loop
  hold only `dt`; all accumulation lives in the resource.
- Wall-clock, UI time, audio time — game-layer concerns; the engine has no
  opinion on them.

# Time Resource — Thought Dump

## Status

**IDEA** — not a task, not a draft, just captured so it doesn't get lost.

---

## The One-Liner

`dt` stays as an explicit `update` parameter — documents time-awareness at
the signature level. `Time` exists as a `Resource.S` for richer time data
that `dt` alone doesn't cover.

```ocaml
(* common case — dt is enough *)
let update world dt = ...

(* richer time needed — fetch the resource *)
let update world _dt =
  let time = Resource.fetch world (module Time) in
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

## Methods

Probably none. `Time.t` is a plain record — data only, no behaviour.
Helpers like `Time.seconds_to_frames` or `Time.fps` can be added later
if a real consumer needs them. Don't add them speculatively.

---

## Who Writes It

`Progress` writes `Time` before dispatching `tick` — it already owns all
the time math (`delta`, `elapsed`, `frame`), so writing the resource is
just making that computation visible to systems. No dedicated `Time_system`
needed, no loop leak, no phase ordering concern. If `Time` is registered,
`Progress` populates it. If not, `Progress` ignores it. Opt-in with zero
cost when unused.

---

## Open Questions (not urgent, just noted)

- Fixed timestep: does `Time.delta` reflect the fixed step or the real
  frame delta? Probably the fixed step during fixed-update systems and
  real delta during variable-update systems — needs thought when Progress
  modes are wired in.
- Pause: does `elapsed` freeze when the game is paused? Probably yes for
  game time, but then you might want a separate `wall_clock_elapsed` for
  UI and audio that ignores pause. Two time resources or one with both?
- Frame 0: is the first frame `frame = 0` or `frame = 1`? Trivial but
  worth deciding once and documenting.

---

## Not Now

After the core loop and Progress modes are settled — Time depends on
knowing exactly what the loop writes each frame.

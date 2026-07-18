# Input System Design — `eon_engine`

## Status

**IMPLEMENTED** (ecs-027 design, ecs-028 implementation).

---

## 1. Scope

This document specifies the input system for `eon_engine`. It covers:

- The `Input_backend.S` abstraction — the platform seam
- `Raw_input_frame.t` — the backend-produced snapshot, including modifier key state
- How `Raw_input_frame` is stored as a world resource each frame
- Frame-order placement — where input fits in the existing collect → tick → drain → render loop
- Mouse coordinate handling — screen space only; world-space transform is the game layer's responsibility
- What NOT to do

The design is intentionally backend-agnostic. No dependency on SDL, raylib, or any
platform library enters `eon_engine`. Platform code lives entirely behind `Input_backend.S`.

The engine makes no decisions about input mapping, action vocabularies, Signal dispatch,
or movement paradigms. Those are game-layer concerns. The engine collects the raw frame
and stores it; games decide what to do with it.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│ Platform (SDL2 / raylib / terminal / null)              │
│                                                         │
│  Input_backend.collect : unit -> Raw_input_frame.t      │
└───────────────────────────┬─────────────────────────────┘
                            │ Raw_input_frame.t
                            ▼
┌─────────────────────────────────────────────────────────┐
│ eon_engine Loop                                         │
│                                                         │
│  World.set_data world Raw_input_frame raw               │
└───────────────────────────┬─────────────────────────────┘
                            │ World resource
                            ▼
┌─────────────────────────────────────────────────────────┐
│ Game layer                                              │
│                                                         │
│  Game-defined Input_system reads Raw_input_frame,       │
│  emits Signals, writes resources, updates state —       │
│  whatever the game needs                                │
└─────────────────────────────────────────────────────────┘
```

---

## 3. Input Backend

### 3.1 Philosophy

The backend follows the Handmade Hero / Casey Muratori platform-layer philosophy:
the engine defines the data structure; the backend fills it in. The entire backend
contract is **one function**:

```ocaml
module type S = sig
  val collect : unit -> Raw_input_frame.t
end
```

Porting to a new platform means implementing that one function. No method
proliferation, no library API leaking into engine code. The backend knows nothing
about the game, the camera, or what the player is doing — it only knows how to
read the current hardware state and produce a snapshot.

### 3.2 Test backends

The single-function contract makes test backends trivial:

```ocaml
module Null = struct
  let collect () = Raw_input_frame.empty
end

module Scripted = struct
  let frames = ref []
  let collect () =
    match !frames with
    | []           -> Raw_input_frame.empty
    | f :: rest    -> frames := rest; f
end
```

`Null` is the default for CI and headless tests. `Scripted` replays a sequence of
pre-built frames — useful for deterministic input tests and replays.

---

## 4. Raw Input Frame

The backend produces a fully pre-computed snapshot each frame. The engine never
diffs consecutive frames — the backend owns that work because it knows whether
its platform exposes raw relative mouse motion (SDL relative mode) or requires
diffing two absolute positions.

```ocaml
type modifiers = {
  shift : bool;
  ctrl  : bool;
  alt   : bool;
  meta  : bool;   (* Windows key / Cmd / Super *)
}

type input_event =
  | Key_down        of Key.t          * float  (* key, time within frame 0.0–1.0 *)
  | Key_up          of Key.t          * float
  | Mouse_down      of Mouse_button.t * float
  | Mouse_up        of Mouse_button.t * float
  | Gamepad_down    of Gamepad_button.t * float
  | Gamepad_up      of Gamepad_button.t * float

type raw_input_frame = {
  (* keyboard *)
  keys_down     : Key_set.t;         (* currently held this frame *)
  keys_pressed  : Key_set.t;         (* edge: up → down this frame *)
  keys_released : Key_set.t;         (* edge: down → up this frame *)
  modifiers     : modifiers;         (* convenience — derived from keys_down by backend *)

  (* mouse *)
  mouse_screen  : int * int;         (* pixels from top-left corner *)
  mouse_delta   : int * int;         (* backend-owned diff, not engine-computed *)
  mouse_buttons_down     : Mouse_button_set.t;
  mouse_buttons_pressed  : Mouse_button_set.t;
  mouse_buttons_released : Mouse_button_set.t;
  scroll_delta  : float;

  (* gamepad — optional; None if no controller connected *)
  gamepad : Gamepad_state.t option;

  (* text input — UTF-8 from OS/IME, independent of key codes; see §4.3 *)
  text_input : string option;

  (* sub-frame event sequence — see §4.2 *)
  events : input_event list;
}

val empty : raw_input_frame
```

Modifier keys (`Key.left_shift`, `Key.right_ctrl`, etc.) appear in `keys_down` /
`keys_pressed` / `keys_released` like any other key. The `modifiers` field is a
convenience record the backend computes from the left+right variants — systems that
only need "is Shift held?" read `frame.modifiers.shift` without scanning the full
key set.

The snapshot is immutable for the duration of a tick. Parallel systems see
consistent input regardless of execution order — there is no mutable input state
that could be read differently by two systems running concurrently.

### 4.1 Gamepad state

```ocaml
type gamepad_state = {
  left_stick  : float * float;    (* normalised direction vector, (-1,-1)..(1,1) *)
  right_stick : float * float;
  buttons_down     : Gamepad_button_set.t;
  buttons_pressed  : Gamepad_button_set.t;
  buttons_released : Gamepad_button_set.t;
  triggers        : float * float;  (* left, right — 0.0..1.0 *)
}
```

Games that need richer gamepad support (haptics, pressure sensitivity, multiple
controllers) implement a new backend — one function.

### 4.2 Sub-frame input resolution

The coarse sets (`keys_pressed`, `keys_released`, etc.) have no ordering or
timestamps within a frame — two keys pressed in the same frame are
indistinguishable. This is fine for the vast majority of game logic. For games
that need sub-frame resolution — fighting game input sequences, rhythm game timing,
precise combo detection — the `events` field provides an ordered, timestamped
record of every input event that occurred during the frame.

Timestamps are normalised to the frame window as `float` in `0.0–1.0`, where `0.0`
is the start of the frame and `1.0` is the end. This keeps the event sequence
frame-relative and independent of wall-clock time.

**Backend responsibility:**

- **Poll-based backends** (raylib): leave `events = []`. They have no sub-frame
  resolution — the coarse sets are all they can provide.
- **Event-driven backends** (SDL): drain the platform event queue in `collect`,
  build the coarse sets AND fill `events` with the ordered sequence, normalising
  timestamps to `0.0–1.0` against the frame duration.

**Consumer responsibility:**

Systems that do not need sub-frame resolution ignore `events` entirely and read
the coarse sets as before. Systems that need ordering or timing read `events`
directly from the `Raw_input_frame` resource. Sub-frame consumers are always
game-layer systems.

```ocaml
(* fighting game combo detector — reads sub-frame event sequence *)
let detect_combo frame =
  frame.events |> List.filter_map (function
    | Key_down (k, t) -> Some (k, t)
    | _               -> None)
  |> match_sequence combo_table
```

The design is **additive** — poll-based backends set `events = []` and pay
nothing. Event-driven backends fill it at no extra cost since they already process
the event queue to build the coarse sets. No existing system changes.

### 4.3 Edge cases the backend must handle

Four subtle correctness requirements that every backend must satisfy. They are not
optional — ignoring any of them produces bugs that are difficult to reproduce and
diagnose.

**Text input.** Key codes alone cannot produce Unicode text. Non-Latin scripts,
dead-key combinations (é, ñ, ü), and IME composition all require the OS to
process key events and emit the resulting text separately. The backend exposes
this as a distinct field:

```ocaml
text_input : string option;  (* UTF-8 string produced by OS/IME this frame;
                                None if no text was composed *)
```

Game systems that need text (chat, name entry, console) read `text_input`.
Systems that need key codes (skill activation, movement) read `keys_pressed` as
before. The two paths are independent — never try to reconstruct text from key
codes.

**Window focus / stuck keys.** When the window loses focus, any key currently
held will never produce a `Key_up` event — the OS swallows it. On the next frame
the game still sees that key in `keys_down`, and it stays there indefinitely.
After alt-tab the player's character keeps walking forever.

The backend must detect focus-loss events and synthesize releases for every key
currently in `keys_down`. On focus regain, `keys_down` must be empty. The frame
the engine produces during a focus-loss frame should reflect the cleared state,
not the stale held state.

**Key repeat suppression.** When a key is held, the OS emits repeated `KeyDown`
events after an initial delay (the typematic rate). The backend must filter these
so that `keys_pressed` fires exactly once per physical press — on the true leading
edge only. Repeated OS events must not appear in `keys_pressed` or in the
`events` list as `Key_down` entries. They may be exposed as a separate
`keys_repeated : Key_set.t` field if text-editing cursor movement needs them, but
they must never contaminate the primary edge sets.

**Gamepad dead zones.** Analog sticks at rest produce small non-zero values due
to hardware drift. Without dead zone filtering, movement input is non-zero every
frame even when the player is not touching the controller. The backend applies a
circular dead zone before normalising the stick vector:

```ocaml
let apply_dead_zone ~threshold (x, y) =
  let mag = sqrt (x *. x +. y *. y) in
  if mag < threshold then (0., 0.)
  else
    let scale = (mag -. threshold) /. (1. -. threshold) in
    (x /. mag *. scale, y /. mag *. scale)
```

The threshold is a backend configuration parameter (typically `0.1`–`0.2`).
The normalised vector stored in `gamepad.left_stick` is always dead-zone-corrected
before it reaches the engine.

---

## 5. Raw Input Frame as World Resource

The loop writes `Raw_input_frame` into the world as a resource at the top of each
frame, before the bus collect phase:

```ocaml
let raw = Platform.Input_backend.collect () in
World.set_data world Raw_input_frame raw
```

Game systems read it directly:

```ocaml
(* game-defined input system — reads raw frame, does whatever the game needs *)
let update world _dt =
  let frame = World.get_data world Raw_input_frame in
  if Key.Set.mem Key.E frame.keys_pressed then Signals.emit `Interact;
  if Mouse_button.Set.mem Left frame.mouse_buttons_pressed then Signals.emit `Click_to_move;
  let dx =
    (if Key.Set.mem Key.D frame.keys_down then 1. else 0.) -.
    (if Key.Set.mem Key.A frame.keys_down then 1. else 0.)
  in
  ...
```

The engine imposes no structure on what happens next. Games that want a data-driven
remappable action table write one. Games that want direct key polling do that.
Games that want to layer combo detection on top of the coarse sets can. The
`Raw_input_frame` resource is the stable handoff point; everything above it is
game logic.

---

## 6. Mouse Coordinates

The backend provides screen-space coordinates only. `mouse_screen` in the raw frame
is the authoritative mouse position — pixels from the top-left corner of the window.

Screen→world coordinate conversion is **not the engine's responsibility**.
The transform is fundamentally projection-dependent:

- **Top-down orthographic**: translate + scale — `(px / zoom + cam_x, py / zoom + cam_y)`
- **Isometric**: invert the isometric projection matrix (2:1 tile shear)
- **3D perspective**: ray cast against a ground plane — not a closed-form 2D transform

These are structurally different operations. The engine has no knowledge of the
game's projection and no business picking one. Game systems that need a world
coordinate perform the transform themselves using their own camera:

```
Engine         → mouse_screen : int * int       (pixels from top-left)
UI systems     → use mouse_screen for button hit-testing, tooltip placement
Game systems   → derive mouse_world via their own screen_to_world
```

---

## 7. Frame Order

Input capture runs at the top of each frame, before the bus collect phase:

```
Platform.Input_backend.collect ()     ← raw snapshot from platform
World.set_data world Raw_input_frame  ← stored as world resource
collect: Signals → Events → Commands
Progress.tick                          (game systems run here, Raw_input_frame already in world)
drain:   Signals → Commands → Events
Platform.Rendering_backend.render stream ~dt
```

Input is not a bus operation — it has no subscribers and no drain phase. The
raw frame write happens directly in the loop body, not inside the pipeline.

---

## 8. Loop Integration

### 8.1 RENDERER removed from `eon_ecs` (done in ecs-028)

The introduction of `Input_backend` as a loop parameter forced a principled
decision about the `eon_ecs` / `eon_engine` boundary. `eon_ecs` Loop.Make
previously carried a `RENDERER` parameter. Adding `INPUT_BACKEND` there too would
have set the precedent for every future platform concern — audio, windowing, asset
loading — to accumulate in the core. That slope ends with a game engine in
`eon_ecs`, not a pure ECS library.

The correct boundary:

- **`eon_ecs`** — pure ECS: entities, components, systems, pipeline, buses. The
  loop is `collect → tick → drain` and nothing else. No renderer, no input, no
  platform opinions.
- **`eon_engine`** — owns all platform seams. Games using the opinionated stack
  use `eon_engine`. Games wanting full control write their own loop around
  `eon_ecs` and place input and rendering wherever they choose.

`RENDERER` has been **removed from `eon_ecs` Loop.Make**. The snake examples
in `eon_ecs` were updated to use a `Variable` render system in a `Render` phase
(ordered after `Gameplay`). This is a small price for a clean, stable core that
does not grow with every new engine concern.

### 8.2 `eon_ecs` Loop — current signature

```ocaml
(* eon_ecs — no platform parameters *)
module Make
    (_ : CLOCK)
    (Progress : ...)
    (_ : BUSES)
  : sig
    val step : ...
    val run  : ...
  end
```

Frame order:

```
collect (buses)
Progress.tick
drain (buses)
```

### 8.3 `eon_engine` Loop and the `Platform.S` signature

Rather than taking a renderer and `Input_backend` as separate functor
parameters, `eon_engine` Loop bundles all platform seams into a single
`Platform.S` module (`eon_engine/platform.mli`):

```ocaml
module type S = sig
  type t
  module Input_backend     : Input_backend.S
  module Audio_backend     : Audio_backend.S
  module Rendering_backend : Rendering_backend.S
end
```

`Loop.Make` then takes the platform as one of its parameters, alongside the
clock, progress controller, and buses (`eon_engine/loop.mli`):

```ocaml
module Make
    (_ : Eon_ecs.Loop.CLOCK)
    (Progress : sig
       type 'phase t
       type world = World.rw World.t
       val tick : 'phase t -> world:world -> dt:float -> world
     end)
    (_ : Platform.S)
    (_ : Eon_ecs.Loop.BUSES)
  : sig ... end
```

**Type safety** — mixing a Raylib renderer with an SDL input backend is a compile
error because they come from different `Platform.S` modules with different
phantom `t` types. You cannot accidentally build an incoherent platform stack.

**Completeness guarantee** — implementing a new platform port means satisfying
`Platform.S`. If `Input_backend` is missing, the compiler says so immediately. As
new platform seams are added to the signature, every existing platform gets a
compile error until the new piece is implemented. The signature is a
compiler-enforced porting checklist — you cannot ship an incomplete port.

Concrete platforms:

```ocaml
module Raylib_platform : Platform.S = struct
  type t = [ `Raylib ]
  module Rendering_backend = Raylib_renderer
  module Input_backend     = Raylib_input
  module Audio_backend     = Raylib_audio
end

module Sdl_platform : Platform.S = struct
  type t = [ `Sdl ]
  module Rendering_backend = Sdl_renderer
  module Input_backend     = Sdl_input
  module Audio_backend     = Sdl_audio
end
```

`Platform.Headless` (shipped in `platform.mli`) bundles all no-ops — one
module, CI runs without a window; see
[rendering_layer_design.md §8](rendering_layer_design.md) and the
`platform_seam.excalidraw` diagram for the full client/server substitution
picture.

### 8.4 UI is not a platform seam — it is a `Render_stream` concern

UI rendering does not belong in the `Platform.S` signature. The platform
trifecta is Rendering, Input, Audio — nothing else. UI rendering is handled
through the `Render_stream` command language via a microui-inspired primitive
vocabulary and a pure OCaml widget collector system.

See [rendering_layer_design.md §11](rendering_layer_design.md) for the full
design: UI primitive commands, the pure OCaml microui collector, the four-layer
stack, and the raygui trade-off.

---

## 9. Module Layout

```
eon_engine/
  input_backend.ml/.mli     (* module type S = sig val collect : unit -> Raw_input_frame.t end *)
  raw_input_frame.ml/.mli   (* backend-produced snapshot; Key_set, Mouse_button_set, Gamepad_state *)
  input_backends/
    null.ml                 (* let collect () = Raw_input_frame.empty *)
    scripted.ml             (* replay a list of pre-built frames *)
    (* sdl.ml, raylib.ml — in game layer, not engine *)
```

The SDL and raylib backends live in the game layer, not `eon_engine` — the engine
has no dependency on external libraries.

---

## 10. What NOT to Do

- **Do not add input mapping or action dispatch to the engine.** The engine stores
  the raw frame. What games do with it — action tables, signal dispatch, combo
  detection, remapping — is entirely their concern. Different games need
  fundamentally different input architectures; the engine must not pick one.

- **Do not do screen→world coordinate conversion in the engine.** The transform is
  projection-dependent — top-down, isometric, and 3D perspective each require
  structurally different math. The engine provides `mouse_screen` only. Game
  systems perform the conversion using their own camera and projection knowledge.

- **Do not fold input capture into the bus collect phase.** Input is not a bus
  operation. The raw frame is written directly in the loop body before collect runs.

- **Do not add methods to the backend.** The backend is one function. If a game
  needs richer platform integration (haptics, IME text input, clipboard), it
  implements a new backend. The `Input_backend.S` signature never grows.

- **Do not apply temporal smoothing or momentum at the input layer.** The raw
  frame reflects hardware state with zero interpretation. Momentum, deceleration
  curves, and movement smoothing are game-layer concerns. Mixing them into the
  input layer makes click-to-move feel laggy and breaks precision techniques like
  kiting. PoE2 tuning movement feel for WASD and breaking click-to-move in the
  process is the canonical example of what goes wrong.

---

## 11. Key Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Backend contract | One function: `collect : unit -> Raw_input_frame.t` | Minimal porting surface; test backends are trivial |
| Delta / edge ownership | Backend | Backend knows whether platform gives relative motion natively |
| Mouse coordinates | Screen space only; game layer derives world | Screen→world is projection-dependent; engine is projection-agnostic |
| Input mapping | None — game layer responsibility | Different games need different architectures; engine must not pick one |
| World resource | `Raw_input_frame` written directly by loop | No processed frame, no engine-defined derived state |
| Frame order | Raw frame written before collect, outside pipeline | Input is not a bus operation |
| `eon_ecs` Loop RENDERER | **Removed** | Adding INPUT_BACKEND alongside would accumulate platform concerns in core; `eon_ecs` loop is `collect → tick → drain` only |
| Platform seams | Owned entirely by `eon_engine` via `Platform.S` sig | Games wanting full control write their own loop around `eon_ecs` |
| `Platform.S` signature | Bundles `Rendering_backend` + `Input_backend` + `Audio_backend` | Type-safe (can't mix platforms); compiler-enforced porting checklist |
| Modifier keys | In `Key_set` like any key + convenience `modifiers` field | Backend computes it; game systems read `frame.modifiers.shift` without scanning full key set |

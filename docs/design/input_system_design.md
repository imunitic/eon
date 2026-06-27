# Input System Design — `eon_engine`

## Status

**DESIGN** (ecs-027). Implementation follows in a later task.

---

## 1. Scope

This document specifies the input system for `eon_engine`. It covers:

- The `Input_backend.S` abstraction — the platform seam
- `Raw_input_frame.t` — the backend-produced snapshot, including modifier key state
- `Modifiers.t` — convenience modifier mask for Shift, Ctrl, Alt, Meta
- The input Exclusive system — transforms raw input into a processed frame and emits Signals
- `Processed_input_frame.t` — the engine-produced resource written into the world
- The input mapping table — raw events → logical actions, stored as a world resource
- Frame-order placement — where input fits in the existing collect → tick → drain → render loop
- Bus integration — what goes into the world resource vs what fires on the Signals bus
- Multiplayer boundary — why input Signals are local-only and commands are distributed
- Mouse coordinate handling — screen space from the backend, world space from the engine
- Movement paradigm — click-to-move primary, WASD secondary
- What NOT to do

The design is intentionally backend-agnostic. No dependency on SDL, raylib, or any
platform library enters `eon_engine`. Platform code lives entirely behind `Input_backend.S`.

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
│ Input system  (Exclusive — World.rw access)             │
│                                                         │
│  1. reads mapping table from world resource             │
│  2. reads camera resource → screen→world transform      │
│  3. builds Processed_input_frame.t                      │
│  4. writes it into world via World.set_data             │
│  5. emits action-slot Signals on local Signals bus      │
└──────────┬──────────────────────────┬───────────────────┘
           │ World resource           │ Local Signals bus
           │ (polled by systems)      │ (subscribed by systems)
           ▼                          ▼
  movement system             skill system
  UI system                   inventory system
  aim system                  interact system
           │
           │ resolved game commands
           ▼
    Distributed bus  →  remote clients
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

Left stick maps to `Move_direction` through the same logical action table as WASD.
Buttons map through the same table as keyboard keys. Games that need richer gamepad
support (haptics, pressure sensitivity, multiple controllers) implement a new
backend — one function.

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
directly from `frame.raw.events` in the processed frame. The mapping table and
input system operate only on the coarse sets — sub-frame consumers are always
game-layer systems.

```ocaml
(* fighting game combo detector — reads sub-frame event sequence *)
let detect_combo frame =
  frame.raw.events |> List.filter_map (function
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
currently in `keys_down`. On focus regain, `keys_down` must be empty. The
processed frame the engine produces during a focus-loss frame should reflect the
cleared state, not the stale held state.

**Key repeat suppression.** When a key is held, the OS emits repeated `KeyDown`
events after an initial delay (the typematic rate). The backend must filter these
so that `keys_pressed` fires exactly once per physical press — on the true leading
edge only. Repeated OS events must not appear in `keys_pressed` or in the
`events` list as `Key_down` entries. They may be exposed as a separate
`keys_repeated : Key_set.t` field if text-editing cursor movement needs them, but
they must never contaminate the primary edge sets.

**Gamepad dead zones.** Analog sticks at rest produce small non-zero values due
to hardware drift. Without dead zone filtering, `Move_direction` is non-zero
every frame even when the player is not touching the controller, causing constant
phantom movement. The backend applies a circular dead zone before normalising the
stick vector:

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

## 5. Input Mapping Table

### 5.1 Structure

The mapping table decouples raw device events from logical game actions. It is a
world resource, loaded at startup from EDN or compiled directly into game code.

Each entry pairs a **binding** (raw event + optional modifier mask) with an
**action**:

```ocaml
type binding = {
  event     : raw_event;         (* Key k | Mouse_button b | Gamepad_button b | ... *)
  modifiers : modifiers option;  (* None = fire regardless of modifiers;
                                    Some m = all true fields in m must be held *)
}
```

The input system fires an entry when the raw event edge occurs AND the current
`frame.modifiers` satisfies the mask. `None` means "any modifier state is fine."
`Some { shift=true; ctrl=false; alt=false; meta=false }` means "Shift must be
held; Ctrl/Alt/Meta are ignored" — the check is `required fields are true`, not
`modifier state equals mask exactly`. This covers the 80/20: plain bindings and
single-modifier combos. Distinguishing "Shift only, not Shift+Ctrl" is a game
concern handled by ordering entries (more specific entries first).

```ocaml
let b event = { event; modifiers = None }
let bm event modifiers = { event; modifiers = Some modifiers }
let shift = { shift=true; ctrl=false; alt=false; meta=false }

World.set_data world Input_mapping [
  b `Mouse_left_click,                      `Move_to;
  b (`Mouse_right_click),                   `Emit `Primary_attack;
  b (`Key Key.a),                           `Move_direction (-1., 0.);
  b (`Key Key.d),                           `Move_direction  (1., 0.);
  b (`Key Key.w),                           `Move_direction  (0., -1.);
  b (`Key Key.s),                           `Move_direction  (0.,  1.);
  b (`Key Key.digit_1),                     `Emit (`Skill_slot_pressed 1);
  bm (`Key Key.digit_1) shift,              `Emit (`Skill_slot_pressed 9);   (* shift+1 = row 2 *)
  b (`Key Key.digit_2),                     `Emit (`Skill_slot_pressed 2);
  bm (`Key Key.digit_2) shift,              `Emit (`Skill_slot_pressed 10);
  b (`Key Key.e),                           `Emit `Interact;
  b (`Key Key.i),                           `Emit `Open_inventory;
  b `Gamepad_left_stick,                    `Move_direction_analog;
]
```

### 5.2 Action vocabulary

Logical actions are open polymorphic variants — the engine defines a base set, the
game extends it freely, and systems pattern-match on what they care about:

```ocaml
(* engine base actions *)
`Move_to                       (* mouse click → world-space destination *)
`Move_direction of float * float  (* WASD / gamepad stick → normalised vector *)
`Move_direction_analog            (* gamepad left-stick → live analog vector *)
`Primary_attack
`Secondary_attack

(* game-defined — engine knows nothing about these *)
`Skill_slot_pressed of int
`Interact
`Open_inventory
`Open_map
`Open_character
`Flask of int
```

### 5.3 Mapping entry kinds

Each entry's action has one of two kinds:

| Kind | Effect |
|------|--------|
| `Move_to` / `Move_direction` | Written into `Processed_input_frame` resource |
| `` `Emit action `` | Fires `action` as a Signal on the local Signals bus |

The input system reads the table, checks each binding's event edge and modifier
mask against the current frame, and dispatches matching entries.

### 5.4 EDN loading

The mapping table can be loaded from an EDN file, enabling user remapping without
recompilation:

```edn
{:input-mapping
  [{:event :mouse-left-click,                         :action :move-to}
   {:event :key-1,                                    :action [:emit :skill-slot-pressed 1]}
   {:event :key-1, :modifiers {:shift true},          :action [:emit :skill-slot-pressed 9]}
   {:event :key-e,                                    :action [:emit :interact]}]}
```

The EDN loader (future ecs-028) parses this into the same `(binding * action)
list` that game code would write directly. The mapping table resource is identical
regardless of whether it came from EDN or OCaml.

---

## 6. Frame Order

Input capture is a dedicated step at the top of each frame, before the bus
collect phase. It does not fold into bus collect — input is not a bus operation,
it has no subscribers and no drain phase:

```
Input_backend.collect          ← new: raw snapshot from platform
Input system tick              ← new: transform → Processed_input_frame + emit Signals
collect: Signals → Events → Commands
Progress.tick                  (parallel systems, including gameplay systems)
drain:   Signals → Commands → Events
Renderer.render
```

The input system runs in the **first pipeline phase**, before all gameplay phases.
All other phases declare themselves `after` the input phase via the pipeline's
`before`/`after` ordering. This guarantees that when a gameplay system runs, the
`Processed_input_frame` resource is already in the world.

The input Exclusive system has `World.rw` access — it needs it to write the
resource and to read the camera resource for the coordinate transform.

---

## 7. Processed Input Frame

The engine input system produces a richer frame than the raw backend snapshot:

```ocaml
type processed_input_frame = {
  (* raw backend snapshot — always available for systems that need it *)
  raw           : raw_input_frame;

  (* mouse coordinates — two spaces *)
  mouse_screen  : int * int;         (* pixels; for UI and HUD systems *)
  mouse_world   : float * float;     (* world space; for gameplay systems *)
  mouse_delta   : int * int;         (* from raw frame *)

  (* movement intent — derived from mapping table *)
  move_to       : (float * float) option;   (* Some pos if left-clicked this frame *)
  move_direction : (float * float) option;  (* Some dir if WASD/stick held *)
}
```

This is written into the world as a resource each frame:

```ocaml
World.set_data world Input_frame processed
```

Systems read it directly:

```ocaml
(* movement system *)
match World.get_data world Input_frame with
| None -> ()
| Some frame ->
  (match frame.move_to with
   | Some dest -> emit_move_command world entity dest
   | None ->
     match frame.move_direction with
     | Some dir -> apply_direction_movement world entity dir
     | None     -> ())
```

---

## 8. Mouse Coordinate Transform

The backend provides screen-space coordinates only — it knows nothing about the
camera. The engine input system performs the screen→world transform using the
camera resource:

```
Backend        → mouse_screen : int * int       (pixels from top-left)
Engine input   → mouse_world  : float * float   (game world coordinates)
Game systems   → use mouse_world for targeting, skill aim, pathfinding
UI systems     → use mouse_screen for button hit-testing, tooltip placement
```

The transform reads the camera component from the world. For a 2D ARPG with an
orthographic fixed camera this is a translate + scale:

```ocaml
let screen_to_world camera (px, py) =
  let wx = (float px -. camera.offset_x) /. camera.zoom +. camera.pos_x in
  let wy = (float py -. camera.offset_y) /. camera.zoom +. camera.pos_y in
  (wx, wy)
```

The engine input system is the only place this transform is applied. Game systems
never do screen→world conversion themselves.

---

## 9. Bus Integration

### 9.1 Hybrid: resource for continuous state, Signals for one-shot actions

Two input modalities exist in an ARPG:

| Modality | Example | Mechanism |
|----------|---------|-----------|
| Continuous | movement direction, mouse aim | `Processed_input_frame` world resource, polled each frame |
| One-shot | skill activation, interact, menu open | Signal emitted once per edge event |

The `Processed_input_frame` resource handles everything that needs to be sampled
every frame. Signals handle everything that should fire exactly once per press,
regardless of how many systems subscribe.

### 9.2 Signal payload

Action Signals carry only the abstract action — the input system is ignorant of
game entities:

```ocaml
`Skill_slot_pressed 1
`Skill_slot_pressed 2
`Interact
`Open_inventory
```

The input system does not know who the player is. Systems that subscribe look up
the player entity from the world themselves:

```ocaml
let on_signal (world : World.rw World.t) = function
  | `Skill_slot_pressed slot ->
    let player = World.get_data world Player_entity in
    activate_skill world player slot
  | _ -> ()
```

This makes skill systems fully testable without any input infrastructure — just
emit `` `Skill_slot_pressed 1 `` directly in tests.

### 9.3 Multiplayer boundary

Input Signals are **local-only** and never cross the network:

```
Local machine
  Input_backend.collect
  Input system → `Skill_slot_pressed 1  (local Signals bus only)
  Skill system → subscribes, resolves intent into game command
               → `Cast_skill (player, 1, target_pos)  (distributed bus)

Remote clients
  receive `Cast_skill (player, 1, target_pos)
  never see `Skill_slot_pressed 1
```

Different clients can have entirely different input schemes (keyboard, gamepad,
touch, accessibility devices) and produce identical distributed commands. The
server validates commands, not raw inputs. Remote clients never need the mapping
table.

This satisfies the constraint from the multiplayer design: all distributed bus
payloads are plain algebraic data (`Cast_skill`, `Move_to`, `Apply_damage`) — not
raw input events.

---

## 10. Movement Paradigm

### 10.1 Click-to-move is primary

Click-to-move is the canonical movement mode. The mouse drives both movement and
aim, distributing input correctly across both hands:

- **Right hand** (mouse): movement destination AND aim direction — constantly engaged
- **Left hand** (keyboard): entire key range free for skills, flasks, utility — no reserved keys

`Move_to (float * float)` is a world-space destination produced by a left-click.
The movement system pathfinds or steers the character toward it.

### 10.2 WASD is secondary

WASD is supported because players expect it, not because it is the better
paradigm. It produces `Move_direction (float * float)` — a normalised direction
vector. The movement system applies velocity in that direction.

WASD and click-to-move are **distinct logical actions**, not aliases. The movement
system handles both; neither path contaminates the other. A click cancels WASD
momentum by producing a `Move_to` which takes priority; releasing all WASD keys
produces no direction and the character stops.

### 10.3 Ergonomic cost of WASD in ARPGs

WASD pins the left hand to movement, removing Q/E/R/F from comfortable reach for
skills. You cannot cleanly hold W (forward) and press E (middle finger, same hand
position) simultaneously. Skill activation and movement become mutually exclusive
in practice, forcing players to choose between moving and casting.

Click-to-move avoids this entirely: movement and skill use are on different hands
and mechanically independent. Both can happen simultaneously with no finger
conflict.

Gamepad left-stick maps to `Move_direction_analog` — same as WASD but with analog
magnitude, giving smoother movement on a controller without affecting the
keyboard path.

---

## 11. Loop Integration

### 11.1 Removing RENDERER from `eon_ecs`

The introduction of `Input_backend` as a loop parameter forces a principled
decision about the `eon_ecs` / `eon_engine` boundary. `eon_ecs` Loop.Make
currently carries a `RENDERER` parameter. Adding `INPUT_BACKEND` there too would
set the precedent for every future platform concern — audio, windowing, asset
loading — to accumulate in the core. That slope ends with a game engine in
`eon_ecs`, not a pure ECS library.

The correct boundary:

- **`eon_ecs`** — pure ECS: entities, components, systems, pipeline, buses. The
  loop is `collect → tick → drain` and nothing else. No renderer, no input, no
  platform opinions.
- **`eon_engine`** — owns all platform seams. Games using the opinionated stack
  use `eon_engine`. Games wanting full control write their own loop around
  `eon_ecs` and place input and rendering wherever they choose.

`RENDERER` is therefore **removed from `eon_ecs` Loop.Make** as part of this
task. The snake examples in `eon_ecs` that currently pass a renderer to
`Loop.Make` will need minor updates — rendering moves outside the loop or into a
drain-phase system. This is a small price for a clean, stable core that does not
grow with every new engine concern.

### 11.2 `eon_ecs` Loop after the change

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

### 11.3 `eon_engine` Loop and the PLATFORM signature

Rather than taking `Renderer` and `Input_backend` as separate functor parameters,
`eon_engine` Loop bundles all platform seams into a single `PLATFORM` module:

```ocaml
module type PLATFORM = sig
  type t                              (* phantom tag — [`Raylib] | [`Sdl] | [`Headless] *)
  module Renderer      : Renderer.S
  module Input_backend : Input_backend.S
  (* future platform seams join here: Audio_backend, Window, etc. *)
end
```

`Loop.Make` then takes one platform parameter:

```ocaml
module Make
    (Clock    : Clock.S)
    (Progress : Progress_adapter.S)
    (Platform : PLATFORM)
    (Buses    : Loop_buses.S)
  : S
```

**Type safety** — mixing a Raylib renderer with an SDL input backend is a compile
error because they come from different `PLATFORM` modules with different phantom
`t` types. You cannot accidentally build an incoherent platform stack.

**Completeness guarantee** — implementing a new platform port means satisfying
`PLATFORM`. If `Input_backend` is missing, the compiler says so immediately. As
new platform seams are added to the signature (audio, windowing), every existing
platform gets a compile error until the new piece is implemented. The signature is
a compiler-enforced porting checklist — you cannot ship an incomplete port.

Concrete platforms:

```ocaml
module Raylib : PLATFORM = struct
  type t = [ `Raylib ]
  module Renderer      = Raylib_renderer
  module Input_backend = Raylib_input
end

module Sdl : PLATFORM = struct
  type t = [ `Sdl ]
  module Renderer      = Sdl_renderer
  module Input_backend = Sdl_input
end
```

The headless platform bundles all no-ops — one module, CI runs without a window:

```ocaml
module Headless : PLATFORM = struct
  type t = [ `Headless ]
  module Renderer      = Noop_renderer
  module Input_backend = Noop_input
end
```

Frame order:

```
Platform.Input_backend.collect world   ← reads hardware, writes Raw_input_frame
collect (buses)
Progress.tick
  Input_system (first phase)           ← transforms raw frame, writes Processed_input_frame, emits Signals
  ... gameplay systems ...
drain (buses)
Platform.Renderer.render world ~dt
```

### 11.4 UI is not a platform seam — it is a RenderGraph concern

Immediate mode GUI libraries (microui, raygui, imgui) are not a fourth PLATFORM
member. UI rendering belongs in the RenderGraph command language.

The insight from microui: a tiny, fixed vocabulary of drawing primitives is
sufficient to build any UI — rect, text, texture, clip. Everything (buttons,
panels, scroll areas, inventory grids) reduces to those four. Applied to the
RenderGraph, this means defining a small set of UI primitive commands using the
same open polymorphic variant extension mechanism planned for the render command
language:

```ocaml
(* UI primitives in the RenderGraph command language *)
`Ui_rect      of { rect: Rect.t; color: Color.t }
`Ui_text      of { pos: Vec2.t; text: string; font: Font_id.t; color: Color.t }
`Ui_texture   of { rect: Rect.t; texture: Texture_id.t; color: Color.t }
`Ui_ninepatch of { rect: Rect.t; texture: Texture_id.t; border: int }
`Ui_clip      of Rect.t
`Ui_end_clip
```

Any UI implementation — microui, raygui, imgui, hand-written — outputs these
commands into the RenderGraph. The renderer backend implements them once,
alongside sprites and meshes. Consequences:

- **PLATFORM trifecta stays clean** (Renderer, Input, Audio) — no `Ui_backend`
  needed because UI rendering goes through the existing renderer backend
- **UI library is decoupled from the renderer** — swapping UI libraries means
  changing what emits the commands, not how they are rendered
- **Z-ordering and batching come for free** — UI commands sit in the same command
  stream as everything else, sorted by the RenderGraph
- **Vocabulary proven minimal** — microui ships real games with exactly these
  primitives

The full stack is four layers, each with a single responsibility:

```
Game code  →  Microui API  (pure OCaml widget logic — no drawing, no C FFI)
                ↓ produces typed command list
             RenderGraph UI commands  (`Ui_rect | `Ui_text | `Ui_clip | ...)
                ↓ emitted by UI collector system into RenderGraph
             Renderer backend  (Raylib: DrawRectangle / DrawText / BeginScissorMode
                                SDL:    SDL_RenderFillRect / TTF_RenderText / ...)
```

**Pure OCaml microui** is the widget logic layer — button state, layout, scroll
areas, focus management — translated directly from the C microui architecture.
C microui already separates widget logic from rendering via a command buffer; the
OCaml version makes that command buffer typed open variants for the RenderGraph
instead of a C union. No C FFI in the core UI layer. The C stays in the backend
where it belongs.

**The UI collector** is a regular `World.ro` ECS system. It reads
`Processed_input_frame` from the world (mouse position, clicks — already there
from the input system), feeds it to the microui context, runs the widget logic for
the current frame, and emits the resulting command list into the RenderGraph. No
special pipeline machinery needed — it is just a system.

```ocaml
(* UI collector system — World.ro, parallel *)
let update world _dt =
  let ctx   = World.get_data world Ui_context in
  let input = World.get_data world Input_frame in
  Microui.set_mouse ctx input.mouse_screen input.raw.mouse_buttons_down;
  (* game UI code *)
  Microui.begin_frame ctx;
  if Microui.button ctx "Attack" then Signals.emit world `Attack_pressed;
  Microui.end_frame ctx;
  (* flush commands into RenderGraph *)
  Microui.iter_commands ctx (fun cmd ->
    Render_graph.emit world (microui_to_render_cmd cmd))
```

The renderer backend IS the microui renderer — not a separate library, not a
separate dependency. It is part of `Raylib_renderer`'s command dispatch alongside
sprite and mesh commands. Porting to SDL means implementing the same ~6 UI
primitive commands in `Sdl_renderer`. UI portability is free.

Properties of this design:

- **Pure OCaml microui is fully testable** — no backend, no window; just verify
  the command list it produces
- **Any backend gets full UI by implementing 6 commands** — rect, text, texture,
  ninepatch, clip, end-clip
- **Input flows naturally** — the UI collector reads `Processed_input_frame`
  already in the world; no special input path needed
- **Z-ordering is free** — UI commands sit in the same RenderGraph stream as
  sprites and meshes

**Trade-off with immediate mode toolkits (raygui).** raygui is incompatible with
this model. It is an immediate mode widget library that calls raylib drawing
functions directly — `GuiButton(rect, "label")` draws immediately and returns
whether it was clicked. It does not emit a command buffer; it bypasses the
RenderGraph entirely. Choosing the RenderGraph primitive vocabulary means giving
up raygui's widget set at the game UI layer.

For shipping game UI this is the right call — an ARPG never uses `GuiButton`
anyway, it builds custom health bars, skill icons, and inventory panels from
rect + text + texture + clip. For rapid prototyping and debug tooling, where
raygui shines, an escape hatch is available:

```ocaml
`Platform_native of (unit -> unit)   (* raw callback — bypasses RenderGraph *)
```

Debug UI and dev tools call raygui (or any platform-native toolkit) directly
through this callback. Game UI uses the proper primitive vocabulary. The escape
hatch is explicitly non-portable and must never appear in shipping game code.

This is a decision for the RenderGraph design task — noted here because the
PLATFORM boundary discussion surfaced it.

---

## 12. Module Layout

```
eon_engine/
  input_backend.ml/.mli     (* module type S = sig val collect : unit -> Raw_input_frame.t end *)
  raw_input_frame.ml/.mli   (* backend-produced snapshot; Key_set, Mouse_button_set, Gamepad_state *)
  processed_input_frame.ml/.mli  (* engine-produced resource; mouse_screen, mouse_world, move_to, etc. *)
  input_mapping.ml/.mli     (* mapping table type; raw_event * action entry list *)
  input_system.ml/.mli      (* Exclusive_def; collect → transform → write resource + emit Signals *)
  input_backends/
    null.ml                 (* let collect () = Raw_input_frame.empty *)
    scripted.ml             (* replay a list of pre-built frames *)
    (* sdl.ml, raylib.ml — in game layer, not engine *)
```

The SDL and raylib backends live in the game layer, not `eon_engine` — the engine
has no dependency on external libraries.

---

## 13. What NOT to Do

- **Do not apply temporal smoothing or momentum at the input layer.** The input
  system outputs raw intent — `Move_to (x, y)` or `Move_direction (dx, dy)` —
  with zero dampening. Momentum, deceleration curves, and movement smoothing are
  physics/movement system concerns applied on top of that intent. Mixing them into
  the input pipeline makes click-to-move feel laggy and breaks precision techniques
  like kiting (click backward, pivot, maintain fire) because the character starts
  lagging behind the player's cursor. PoE2 tuning movement feel for WASD and
  breaking click-to-move in the process is the canonical example of what goes
  wrong.

- **Do not let the input system know about game entities.** It does not know who
  the player is, what skills exist, or what the current scene contains. It emits
  abstract actions (`Skill_slot_pressed 1`) and writes geometry (mouse world
  position). Entity resolution belongs to the subscribing system.

- **Do not send input events over the network.** Local Signals carry raw intent
  and stay on the local machine. Only resolved game commands (`Cast_skill`,
  `Move_to`) go on the distributed bus. Remote clients never need the mapping
  table.

- **Do not do screen→world coordinate conversion in game systems.** That
  transform happens once, in the input system, using the camera resource. Game
  systems always receive world coordinates from the processed frame.

- **Do not fold input capture into the bus collect phase.** Input is not a bus
  operation. It runs as a dedicated step before collect, implemented as an
  Exclusive system in the first pipeline phase.

- **Do not add methods to the backend.** The backend is one function. If a game
  needs richer platform integration (haptics, IME text input, clipboard), it
  implements a new backend. The `Input_backend.S` signature never grows.

---

## 14. Key Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Backend contract | One function: `collect : unit -> Raw_input_frame.t` | Minimal porting surface; test backends are trivial |
| Delta / edge ownership | Backend | Backend knows whether platform gives relative motion natively |
| Mouse coordinates | Backend gives screen; engine gives world | Backend has no camera knowledge |
| Frame order | Dedicated step before collect, first pipeline phase | Input is not a bus; snapshot must precede all gameplay systems |
| Bus integration | Hybrid: resource for continuous, Signals for one-shot | Matches ARPG modality split; Signals decouple skill systems from input |
| Action vocabulary | Open polymorphic variants | Engine defines base set; game extends freely; consistent with command buses |
| Mapping table storage | World resource (EDN-loadable) | Remappable; survives scene transitions; consistent with data plane |
| Movement primary | Click-to-move (`Move_to`) | Correct two-hand load distribution; WASD is secondary (`Move_direction`) |
| Multiplayer boundary | Input Signals are local-only | Distributed bus carries only resolved game commands |
| Gamepad scope | Essential only (left-stick + buttons via action table) | Backend seam makes extension trivial; no over-engineering |
| Modifier keys | In `Key_set` like any key + convenience `modifiers` field | Backend computes it; systems read `frame.modifiers.shift` not full key scan |
| Modifier combos | Optional mask on binding; required-fields-true check | Covers 80/20 (plain + single-modifier); ordering handles specificity |
| `eon_ecs` Loop RENDERER | **Removed** | Adding INPUT_BACKEND alongside it would set a precedent for audio, windowing, etc. to accumulate in core; `eon_ecs` loop is `collect → tick → drain` only |
| Platform seams | Owned entirely by `eon_engine` via `PLATFORM` sig | Games wanting full control write their own loop around `eon_ecs` |
| PLATFORM signature | Bundles Renderer + Input_backend (+ future seams) | Type-safe (can't mix platforms); compiler-enforced porting checklist |

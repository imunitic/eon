# Eon Engine Rendering Layer Design Document

**Status**: Architectural design. Examples are illustrative; API details will be refined during implementation.

## 1. Overview

The rendering layer is backend-agnostic: the engine defines a data vocabulary and the infrastructure to populate it; the backend decides how to render it. The engine and ECS core have no opinion on rendering technique, draw order, or shader usage.

Four components collaborate to produce a frame:

1. **Render_stream** — an ordered world-space command list and a screen-space command list; no entity references. The stream is the data contract between the ECS tick and the render call.
2. **Render_stream_collector** — runs game-supplied collectors sequentially to populate the stream each frame.
3. **Render_system** — a standard ECS system that clears the stream, runs the collector, and stores the result in the world data plane. It never calls the backend.
4. **Rendering_backend** — receives the populated stream and produces pixels. Called by the engine loop after drain, via `Platform.S`.

### Frame Flow

```
1. collect  — Signals → Events → Commands
2. tick     — Progress.tick; Render_system runs:
                clear Render_stream → run Render_stream_collector → store reference in data plane
3. drain    — Signals → Commands → Events
4. render   — engine loop reads Render_stream from data plane,
               calls Platform.Rendering_backend.render graph ~dt
```

The world data plane is the handoff point between tick and render. `eon_ecs` Loop stays `collect → tick → drain` only — the render slot is exclusively an `eon_engine` concern.

## 2. Base Command Set

Seven backend-agnostic commands cover a complete 2D game. The command stream is ordered — collectors run sequentially in registration order, and the backend processes commands in the order they appear. This gives the backend a fully deterministic, ordered buffer to work with; batching, grouping by camera, and sorting by layer are all backend responsibilities.

```ocaml
(* render_commands.mli *)

type rect  = { x : float; y : float; w : float; h : float }
type color = { r : float; g : float; b : float; a : float }

type command = [
  | `Clear_background of color

  | `Set_camera of {
      position : float * float;
      zoom     : float option;
      rotation : float option;       (* radians; None = 0.0 *)
      target   : (float * float) option;
      viewport : rect option;        (* None = full screen *)
    }

  | `Draw_texture of {
      texture_id : string;
      source     : rect option;  (* None = full texture; Some r = sprite sheet region *)
      dest       : rect;
      rotation   : float option;
      origin     : (float * float) option;  (* rotation pivot, dest-local coords *)
      tint       : color option;
      layer      : int;
    }

  | `Draw_text of {
      text     : string;
      position : float * float;
      font_id  : string;
      size     : float;
      color    : color;
      layer    : int;
    }

  | `Draw_rect   of { rect   : rect;   color : color; filled : bool; layer : int }
  | `Draw_circle of { center : float * float; radius : float; color : color; filled : bool; layer : int }
  | `Draw_line   of { start  : float * float; stop : float * float; thickness : float; color : color; layer : int }
]
```

`Draw_texture` unifies texture, sprite, and image drawing via the optional `source` rect. Animation is not a render command — `Animation_system` updates the source rect on the `Sprite` component each tick; the collector emits the current frame. `tint` enables hit flash, transparency, and colour effects without a shader. `filled` covers both fill and outline variants with one command.

A backend extends the base set via polymorphic variant inclusion:

```ocaml
type command = [
  | Render_commands.command
  | `Apply_shader   of shader
  | `Draw_particles of particle_system
]
```

## 3. Render_stream

The stream holds two coordinate spaces. **World space** is an ordered list of commands — `Set_camera` followed by draw commands, repeated for each camera. **Screen space** is a flat list fixed to the screen regardless of camera; HUD, UI, damage numbers.

The ordering of world-space commands is meaningful: `Set_camera` establishes the camera context for the draw commands that follow it, until the next `Set_camera`. The collector produces a deterministic command stream; a backend may consume it directly or perform arbitrary preprocessing — grouping, sorting, batching, culling, command-buffer generation — before issuing draw calls.

```ocaml
(* render_stream.mli *)

type 'command t  (* abstract *)

val create     : unit -> 'command t
val clear      : 'command t -> unit
val add_world  : 'command t -> 'command -> unit
val add_screen : 'command t -> 'command -> unit
val iter_world  : 'command t -> ('command -> unit) -> unit
val iter_screen : 'command t -> ('command -> unit) -> unit
```

The backend iterates the world stream and tracks camera state as it goes:

```ocaml
(* Raylib backend — naive single-pass implementation for illustration.
   A real backend would do a pre-pass to group commands by camera, then
   render each group cleanly with no stateful camera_active bookkeeping.
   A sophisticated backend can go further and construct a full internal
   render graph — dependency DAG, reordered passes, batching, state deduplication —
   before issuing a single draw call. The stream is the contract; what happens
   behind it is entirely the backend's business. *)
let render graph ~dt:_ =
  Raylib.begin_drawing ();
  let camera_active = ref false in
  Render_stream.iter_world graph (function
    | `Set_camera cam ->
        if !camera_active then Raylib.end_mode_2d ();
        Raylib.begin_mode_2d (to_raylib_camera cam);
        camera_active := true
    | cmd -> dispatch cmd
  );
  if !camera_active then Raylib.end_mode_2d ();
  Render_stream.iter_screen graph dispatch_screen;
  Raylib.end_drawing ()
```

A backend extends the base set using polymorphic variant inclusion and is wired once through `Platform.S`:

```ocaml
module OpenGL_platform : Platform.S = struct
  type t = [ `OpenGL ]
  module Rendering_backend = OpenGL_rendering_backend
  module Input_backend     = Glfw_input_backend
end
```

## 4. Render_stream_collector

The `Render_stream_collector` organises collectors into named phases, mirroring how `Pipeline` organises systems. Phases execute in declaration order; collectors within a phase execute in addition order. Both are sequential — no coordination overhead, deterministic command stream.

Phases are an organisational tool, not a performance boundary. They make the rendering structure immediately readable: `Camera` → `World` → `Effects` tells you the frame's rendering intent at a glance, without having to trace through a flat list of `add_collector` calls. They also structurally guarantee that `Set_camera` precedes draw commands — a `Camera` phase always runs before a `World` phase, no documentation required.

Collection is not the performance bottleneck; the backend is. The ordered command buffer the collector produces is what the backend batches, sorts, and optimises.

A collector is `World.ro World.t -> 'command Render_stream.t -> unit`. `World.ro` is enforced by type — collectors never mutate world state. The engine ships no collectors; it cannot know which components a game uses or how rendering data is structured.

```ocaml
(* render_stream_collector.mli *)

type ('phase, 'command) t
type 'command collector = World.ro World.t -> 'command Render_stream.t -> unit

val create        : unit -> ('phase, 'command) t
val add_phase     : 'phase -> ('phase, 'command) t -> ('phase, 'command) t
(* Idempotent — if the phase already exists, t is returned unchanged.
   Allows feature modules to declare the phases they need without coordination. *)
val add_collector : 'phase -> 'command collector -> ('phase, 'command) t -> ('phase, 'command) t
val collect       : ('phase, 'command) t -> World.ro World.t -> 'command Render_stream.t -> unit
```

```ocaml
(* Camera collector — one collector per camera role, not one for all cameras.
   A generic "collect all cameras" would emit Set_camera for every camera entity
   in a single phase, breaking multi-camera layouts. Each collector queries
   positively for its role marker — adding a new camera type never breaks existing collectors. *)
let collect_main_camera (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Camera.name
  |> Query.having Components.Main_camera.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let camera = View.get view (module Components.Camera) in
       let target =
         match View.get_opt view (module Components.Camera_target) with
         | None    -> None
         | Some ct ->
           match World.get_component world ct.target_entity Components.Position.component with
           | None   -> None
           | Some p -> Some (p.x, p.y)
       in
       Render_stream.add_world graph (`Set_camera {
         position = (pos.x, pos.y);
         zoom     = Some camera.zoom;
         rotation = camera.rotation;
         target;
         viewport = camera.viewport;
       }))

(* Sprite collector — uniform with every other collector *)
let collect_sprites (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Sprite.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let sprite = View.get view (module Components.Sprite) in
       Render_stream.add_world graph (`Draw_texture {
         texture_id = sprite.texture_id;
         source     = sprite.source_rect;
         dest       = { x = pos.x; y = pos.y; w = sprite.w; h = sprite.h };
         rotation   = None; origin = None; tint = None;
         layer      = sprite.layer;
       }))
```

### Multi-camera and Marker Components

The minimap is not a special case — it is a second lens over the same entities. The same player entity with `Sprite` + `Position` appears in both the main world and the minimap; the collectors simply emit different commands for different camera phases. Queries overlapping across collectors is intentional, not a bug.

The main world collector queries `having Sprite` + `having Position` — the presence of `Sprite` already implies world visibility. No `World_visible` marker is needed.

For minimap visibility, a pure marker (`Minimap_visible`) only makes sense if the minimap reuses the entity's existing `Sprite` as-is. The moment the minimap needs its own visual representation — a specific icon, a different colour, a dot of a specific size — the marker becomes a data component:

```ocaml
(* minimap_icon.mli *)
type t = {
  texture_id : string;
  color      : color;
  size       : float;
}
```

The presence of `Minimap_icon` on an entity is both the opt-in signal and the data source — no separate marker needed, same as `Sprite` implying world visibility. This covers two cases with one component:

- **World entity shown on minimap**: has `Sprite` (world rendering) + `Minimap_icon` (minimap rendering)
- **Minimap-only entity** (waypoint, zone boundary, quest marker): has `Minimap_icon` but no `Sprite`

The minimap collector queries for `Minimap_icon` and handles both cases uniformly:

```ocaml
let collect_minimap world graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Minimap_icon.name
  |> Query.iter (fun view ->
       let pos  = View.get view (module Components.Position) in
       let icon = View.get view (module Components.Minimap_icon) in
       Render_stream.add_world graph (`Draw_texture {
         texture_id = icon.texture_id;
         dest       = { x = pos.x; y = pos.y; w = icon.size; h = icon.size };
         tint       = Some icon.color;
         source     = None; rotation = None; origin = None;
         layer      = 0;
       }))
```

The main world collector never sees `Minimap_icon` entities without a `Sprite` because it never queries for them. Entities with both components appear in both views, each rendered appropriately for its context.

## 5. Rendering_backend

The backend receives an already-populated `Render_stream` and has complete autonomy over rendering decisions. Non-fatal errors are returned in `Rendering_result.t`; truly fatal errors (GPU lost, out of memory) raise exceptions.

```ocaml
(* rendering_result.mli *)
type t = { errors : string list }

val empty      : t
val has_errors : t -> bool
```

```ocaml
(* rendering_backend.mli *)

module type S = sig
  type command

  val init        : unit -> unit
  val render      : command Render_stream.t -> dt:float -> Rendering_result.t
  val diagnostics : unit -> (string * string) list
  (* Returns diagnostic information for the most recently completed render call.
     If per-draw-call diagnostics are ever added, consider iter_diagnostics to avoid
     list allocation on the hot path. *)
  val shutdown    : unit -> unit
end
```

### Asset Loading

There is no central asset manager. Each backend owns its GPU handles and font atlases from `init` to `shutdown`. Game code uses only stable string identifiers (`texture_id`, `font_id`); the backend resolves those to internal handles at render time.

Asset loading is entirely the backend's concern — the loop calls `init ()` and has no knowledge of assets. A backend that wants to scan the asset directory accepts `Asset_lookup.S` as a functor parameter at construction time:

```ocaml
module Raylib_renderer (Assets : Asset_lookup.S) : Rendering_backend.S = struct
  let init () =
    InitWindow (...);
    Assets.iter (fun logical_id path -> preload_texture logical_id path)
  ...
end
```

`Asset_lookup` (in `eon_engine/asset_lookup.ml`) provides `Dir`, `Null`, and `Scripted` implementations as shared utilities — backends that don't need them can ignore them entirely.

The directory structure is the manifest — drop a file in the right folder and it is immediately available:

```
assets/
  sprites/player.png  →  texture_id: "sprites/player.png"
  fonts/ui.ttf        →  font_id:    "fonts/ui.ttf"
```

Hot reloading, streaming, and GC-style eviction can all be layered on top without changing this interface.

## 6. Render_system

```ocaml
(* render_system.mli *)

module Make (B : Rendering_backend.S) : sig
  val make
    :  render_stream_collector:B.command Render_stream_collector.t
    -> Eon_engine.System.Default.t
end
```

The system owns a `Render_stream` created once in `make`. Each frame it clears the stream, runs the collector to repopulate it, then stores a reference in the world data plane for the engine loop to read. No allocation per frame, no double-buffering needed. The system never calls the backend.

`Render_system.Make(My_platform.Rendering_backend)` is the only backend functor application in game code; mismatched collector command types are a compile error. The system should be added to the pipeline after all other systems so that world state is fully updated before collection.

## 7. Platform.S and Loop Integration

```ocaml
(* platform.mli *)

module type S = sig
  type t
  module Rendering_backend : Rendering_backend.S
  module Input_backend     : Input_backend.S
end

module Headless : S  (* null rendering and input; for servers, CI, and tests *)
```

The game names its backend exactly once in its `Platform.S` implementation. `Loop.Make` reads the stream from the world data plane and calls `Platform.Rendering_backend.render` directly — no adapter:

```ocaml
let step ~progress ~world ~last_time ~now ~should_continue =
  let raw = Platform.Input_backend.collect () in
  Raw_input_frame.set world raw;
  Buses.collect ();
  let dt    = now -. last_time in
  let world = Progress.tick progress ~world ~dt in
  Buses.drain ();
  let graph = World.get_data world `Render_stream in
  let result = Platform.Rendering_backend.render graph ~dt in
  if Rendering_result.has_errors result then
    List.iter (fun e -> Printf.eprintf "[renderer] %s\n" e)
      result.errors;
  (world, now, should_continue world)
```

## 8. UI Rendering

Specified in `docs/design/microui_ui_system_design.md`. Deferred until the core rendering layer is implemented.

## 9. Wiring Example

```ocaml
let render_stream_collector =
  Render_stream_collector.create ()
  |> Render_stream_collector.add_phase `Camera
  |> Render_stream_collector.add_phase `World

  |> Render_stream_collector.add_collector `Camera Game.collect_main_camera
  |> Render_stream_collector.add_collector `World  Game.collect_sprites
  |> Render_stream_collector.add_collector `World  Game.collect_particles

module My_render_system = Render_system.Make(My_platform.Rendering_backend)
let render_system = My_render_system.make ~render_stream_collector

let ecs_pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Render
  |> Pipeline.add_system `Render render_system

module Loop = Eon_engine.Loop.Make
  (Eon_ecs.Clock.Mtime)(Engine_progress)(My_platform)(Eon_engine.Loop_buses)

let () =
  let progress = Engine_progress.create ~mode:Progress.Variable pipeline in
  Loop.run ~progress ~world ~should_continue:(fun _ -> true) ()
```

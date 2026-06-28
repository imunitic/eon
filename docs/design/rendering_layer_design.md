# Eon Engine Rendering Layer Design Document

**Design Document Status**: This document contains architectural design decisions and implementation guidelines. Examples are illustrative and subject to iteration in later phases.

## 1. Overview

The rendering layer provides a **backend-agnostic rendering system** where the engine and ECS core have no say in how something is rendered. A rendering backend is the only component that decides the order and method of rendering a `Render_graph`.

This design maintains the core Eon principles:
- **Minimalism**: Backend interface has minimal methods (ideally just `render`)
- **Extensibility**: Pluggable backends via `Platform.S` — the game names its backend once; the type system enforces consistency
- **Decoupling**: Engine doesn't know about rendering details
- **Flexibility**: Backend decides shader usage, rendering order, and techniques

## 2. Core Architecture

### 2.1 Rendering Layer Components

The rendering layer consists of four main components:

1. **Render_graph** — Ordered collection of rendering commands; no entity references
2. **Render_graph_collector** — Phase-ordered collector executor (mirrors ECS Pipeline)
3. **Render_system** — Standard ECS system that drives the Render_graph_collector each tick and stores the graph in the world data plane
4. **Rendering_backend** — Consumes the graph and produces pixels; called by the engine loop via `Platform.Rendering_backend` after drain

### 2.2 Frame Flow

```
Frame Order:
1. Collect: Signals → Events → Commands
2. Tick: Progress.tick (systems run, including Render_system)
   - Render_system clears the Render_graph resource in the world data plane
   - Render_system runs Render_graph_collector (populates Render_graph via collectors)
   - Render_system stores populated Render_graph back into world data plane
     (overwritten each frame — no double-buffering needed)
3. Drain: Signals → Commands → Events
4. Render: engine loop reads Render_graph from world data plane,
           calls Platform.Rendering_backend.render(Render_graph)
```

**Key Points**:
- Render_system is a standard ECS system that runs during the Tick phase
- Render_system never calls the backend — it only builds and stores the Render_graph
- The world data plane is the handoff point between Tick and Render
- the engine loop is the only caller of `Platform.Rendering_backend.render`, always in the Render slot
- The `eon_ecs` loop carries no renderer — the render call happens in the `eon_engine` loop via `Platform.S`
- Render_graph_collector is independent from ECS Pipeline but called by Render_system
- Render_graph_collector runs all collectors fully in parallel — insertion order is irrelevant because the backend decides draw order from the commands themselves

### 2.3 Key Design Principle

**Backend Autonomy**: The rendering backend has complete control over:
- Rendering order (e.g., by layer, by shader, by distance)
- Shader usage (e.g., apply shaders to certain entities, skip for others)
- Rendering techniques (e.g., batching, instancing, culling)
- Output format (e.g., terminal, OpenGL, Vulkan, HTML5 Canvas)

The engine only provides the data; the backend decides how to use it.

## 3. Base Command Set

### 3.1 Purpose

Eon Engine provides a set of backend-agnostic rendering commands that all backends
must handle. These seven commands are sufficient to build a complete 2D game — every
visual element in a 2D game reduces to rectangles, textures, shapes, and text.
Anything beyond this set (particles, shaders, surfaces) is backend extension territory.

### 3.2 Base Commands

```ocaml
(* render_commands.mli *)

type rect  = { x : float; y : float; w : float; h : float }
type color = { r : float; g : float; b : float; a : float }

type command = [
  | `Clear_background of color

  | `Set_camera of {
      position : float * float;
      zoom     : float option;
      rotation : float option;       (** radians; None = 0.0 *)
      target   : (float * float) option;
      viewport : rect option;        (** None = full screen; Some rect for minimap/split *)
    }

  (** Draw a texture or sprite sheet region.
      source = None    → full texture  (equivalent to "draw image")
      source = Some r  → sub-region    (equivalent to "draw sprite frame") *)
  | `Draw_texture of {
      texture_id : string;
      source     : rect option;
      dest       : rect;
      rotation   : float option;
      origin     : (float * float) option;  (* rotation pivot, in dest-local coords *)
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

  | `Draw_rect of {
      rect   : rect;
      color  : color;
      filled : bool;
      layer  : int;
    }

  | `Draw_circle of {
      center : float * float;
      radius : float;
      color  : color;
      filled : bool;
      layer  : int;
    }

  | `Draw_line of {
      start     : float * float;
      stop      : float * float;
      thickness : float;
      color     : color;
      layer     : int;
    }
]
```

**Key Points**:
- Seven commands cover a complete 2D game — all visual elements reduce to rectangles,
  textures, shapes, and text
- `Draw_texture` unifies texture, sprite, and image drawing via the optional `source`
  rect; animation is not a render command — the `Animation_system` updates the source
  rect in the `Sprite` component each tick and the collector emits the current frame
- `layer` on every draw command gives backends full control over draw order
- `tint` on `Draw_texture` enables hit flash, transparency, and colour effects without
  a shader
- `filled` on shapes covers both fill and outline variants with one command
- All backends must implement all seven; anything beyond this set is a backend extension

### 3.3 Collector Pattern

A collector is a function that queries the world and adds commands to the
Render_graph. The engine provides the type and the infrastructure; **the game
writes the collectors** — exactly as the engine provides `System.Parallel_def`
but the game writes the systems.

```ocaml
(* The collector type — defined by the engine, implemented by the game *)
type 'command collector = World.ro World.t -> 'command Render_graph.t -> unit
```

`World.ro` is explicit: collectors never mutate the world. The `[> command]`
lower bound means a collector written against the base command set works with any
backend command type that includes those commands — backends can extend freely
without breaking existing collectors.

A game collector queries its own components and emits base commands:

```ocaml
(* game code — the game knows what components it has *)
let collect_sprites (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Sprite.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let sprite = View.get view (module Components.Sprite) in
       Render_graph.add_world graph (`Draw_texture {
         texture_id = sprite.texture_id;
         source     = sprite.source_rect;
         dest       = { x = pos.x; y = pos.y; w = sprite.w; h = sprite.h };
         rotation   = None;
         origin     = None;
         tint       = None;
         layer      = sprite.layer;
       }))

let collect_cameras (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Camera.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let camera = View.get view (module Components.Camera) in
       Render_graph.add_world graph (`Set_camera {
         position = (pos.x, pos.y);
         zoom     = camera.zoom;
         rotation = camera.rotation;
         target   = None;
         viewport = camera.viewport;
       }))
```

The engine does not ship pre-built collectors. It cannot know which components a
game uses, how its sprite data is structured, or whether it uses cameras at all.

## 4. Render_graph

### 4.1 Purpose

The `Render_graph` is a collection of rendering commands split into two explicit
lists: world-space commands and screen-space commands. It contains no entity
references — just pure rendering instructions that backends can process.

### 4.2 Design

Every 2D backend has the same two coordinate spaces:
- **World space** — moves with the camera; entities, tiles, effects
- **Screen space** — fixed on screen regardless of camera; HUD, UI, damage numbers

Rather than encoding this distinction in a magic layer number, the graph makes it
explicit with two separate lists. The backend iterates each list in the right
coordinate context without inspecting layer values.

```ocaml
(* render_graph.mli *)

module type S = sig
  (** The type of the render graph, parameterized by command type. *)
  type 'command t

  (** Create an empty render graph. *)
  val create : unit -> 'command t

  (** Add a world-space command — drawn inside the camera transform. *)
  val add_world  : 'command t -> 'command -> unit

  (** Add a screen-space command — drawn outside the camera transform; HUD and UI. *)
  val add_screen : 'command t -> 'command -> unit

  (** Clear both lists. *)
  val clear : 'command t -> unit

  (** Iterate world-space commands in insertion order. *)
  val iter_world  : 'command t -> ('command -> unit) -> unit

  (** Iterate screen-space commands in insertion order. *)
  val iter_screen : 'command t -> ('command -> unit) -> unit
end
```

The raylib backend uses the two lists directly:

```ocaml
let render graph ~dt:_ =
  Raylib.begin_drawing ();
  Raylib.clear_background background_color;
  Raylib.begin_mode_2d camera;
  Render_graph.iter_world  graph (fun cmd -> dispatch cmd);
  Raylib.end_mode_2d ();
  Render_graph.iter_screen graph (fun cmd -> dispatch cmd);
  Raylib.end_drawing ()
```

Every other backend follows the same pattern with its own coordinate space API:
SDL uses `SDL_RenderSetScale`, OpenGL pushes/pops projection matrices. The two-list
split is not a raylib convenience — it is a fundamental property of 2D rendering
that all backends share.

**Key Points**:
- Two lists make world/screen space an explicit data property, not a layer convention
- `layer` on world commands is now purely for depth sorting within world space
  (background, ground, entities, effects) — it has no coordinate-space meaning
- Screen-space commands sort among themselves independently
- Graph is generic over command type
- Both `add_*` functions mutate in place — the graph is a mutable accumulator
- No `commands` accessor to avoid O(n) allocation on the hot path; use `iter_*`

### 4.3 Backend Extension Example

A backend extends the base command set using polymorphic variant inclusion and
documents each extended command. The backend lives inside a `Platform.S`
implementation — the platform is the single entry point the game uses:

```ocaml
(* Backend defines and documents its extended command type *)
module OpenGL_rendering_backend = struct
  type command = [
    | Render_commands.command  (* base set *)
    | `Apply_shader    of shader
    | `Set_blend_mode  of blend_mode
    | `Draw_particles  of particle_system
  ]

  let render graph ~dt:_ = (* ... *)
end

(* Platform.S wires the backend in — game names it once here *)
module OpenGL_platform : Platform.S = struct
  type t = [ `OpenGL ]
  module Rendering_backend = OpenGL_rendering_backend
  module Input_backend     = Glfw_input_backend
end

(* Game writes a collector for the extended command — anchored to the platform *)
let collect_particles (world : World.ro World.t)
    (graph : OpenGL_platform.Rendering_backend.command Render_graph.t) =
  Query.from world
  |> Query.having Components.Particle_emitter.name
  |> Query.iter (fun view ->
       let ps = View.get view (module Components.Particle_emitter) in
       Render_graph.add_world graph (`Draw_particles ps))
```

The collector's graph type is anchored to `OpenGL_platform.Rendering_backend.command`.
If the platform changes, the type annotation must be updated — the type system
flags any mismatch at `Render_system.Make(OpenGL_platform.Rendering_backend)`.

## 5. Render_graph_collector

### 5.1 Purpose

The `Render_graph_collector` holds a set of collector functions and runs them all
in parallel to populate the render graph. There are no phases and no ordering edges
— collector order is irrelevant because the backend decides draw order from the
commands themselves, not from insertion order.

Collectors are pure `World.ro` reads with side effects only on the graph. Because
they never mutate shared state they are trivially safe to run concurrently.

### 5.2 Design

`Render_graph_collector` is a functor over `Executor.S` — the same threading seam
used by the ECS pipeline. By default it is instantiated with `Executor.Sequential`;
swapping to `Executor.Domain_pool` makes all collectors run concurrently with no
other code changes.

```ocaml
(* render_graph_collector.mli *)

module type S = sig
  (** Collector set, generic over command type. *)
  type 'command t

  (** Collector function — reads world state, emits commands into the graph.
      World.ro is enforced by type: collectors never mutate world state. *)
  type 'command collector = World.ro World.t -> 'command Render_graph.t -> unit

  (** Create an empty collector set. *)
  val create : unit -> 'command t

  (** Register a collector. *)
  val add_collector : 'command collector -> 'command t -> 'command t

  (** Run all collectors via the configured Executor.
      World is passed at call time — no world reference is stored. *)
  val collect : 'command t -> World.ro World.t -> 'command Render_graph.t -> unit
end

(** Build a collector executor over any Executor.S. *)
module Make (E : Executor.S) : S

(** Default: sequential execution. Zero overhead, correct everywhere. *)
module Default : S
```

**Thread safety via private graphs**: each collector receives its own private
`Render_graph` — never shared with other threads. After `Executor.run_all` returns
(the barrier), the private graphs are merged into the final graph sequentially via
a flat `List.iter`. No mutex anywhere — private graphs have one writer each, and
the merge is single-threaded by construction.

```ocaml
(* inside Render_graph_collector.Make(E).collect *)
let collect t world final_graph =
  let private_graphs = List.map (fun _ -> Render_graph.create ()) t.collectors in
  let jobs = List.map2 (fun collector pg ->
    fun () -> collector world pg
  ) t.collectors private_graphs in
  E.run_all jobs;
  (* run_all is a barrier — all collectors done, merge is sequential *)
  List.iter (fun pg ->
    Render_graph.iter_world  pg (Render_graph.add_world  final_graph);
    Render_graph.iter_screen pg (Render_graph.add_screen final_graph)
  ) private_graphs
```

`Render_graph` needs no synchronization primitives — it stays a plain mutable
record. The N private graph allocations are small, short-lived, and immediately
eligible for GC after the merge.

**Key Points**:
- No phases, no ordering edges — insertion order is irrelevant; backend decides draw order
- `World.ro` guarantees no world mutation; private graphs eliminate all write contention
- `Render_graph` is a plain mutable record — no mutex, no lock-free structures
- Merge is a flat `List.iter` after the executor barrier — trivially sequential
- World is passed at `collect` call time; no world reference stored
- Mirrors `Pipeline.Make` / `Pipeline.Default` — same seam, same swap story

**Swapping to parallel execution**:
```ocaml
(* Sequential — default, zero overhead *)
module Coll = Render_graph_collector.Default

(* Parallel — OCaml 5 Domain pool, true concurrent collector dispatch *)
module Coll = Render_graph_collector.Make(Executor.Domain_pool.Make(struct
  let size = Executor.Domain_pool.recommended_size ()
end))

let render_graph_collector =
  Coll.create ()
  |> Coll.add_collector Game.collect_sprites
  |> Coll.add_collector Game.collect_cameras
  |> Coll.add_collector Game.collect_particles
```

### 5.3 Collector Examples

**Collectors are written by the game** — the engine provides none, backends provide none:

```ocaml
(* Game-written collectors — run fully in parallel *)
let collect_sprites (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Sprite.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let sprite = View.get view (module Components.Sprite) in
       Render_graph.add_world graph (`Draw_texture {
         texture_id = sprite.texture_id;
         source     = sprite.source_rect;
         dest       = { x = pos.x; y = pos.y; w = sprite.w; h = sprite.h };
         rotation   = None;
         origin     = None;
         tint       = None;
         layer      = sprite.layer;
       }))

let collect_cameras (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Camera.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let camera = View.get view (module Components.Camera) in
       let target =
         match View.get_opt view (module Components.Camera_target) with
         | None -> None
         | Some ct ->
           (match World.get_component world ct.target_entity Components.Position.component with
            | None -> None
            | Some p -> Some (p.x, p.y))
       in
       Render_graph.add_world graph (`Set_camera {
         position = (pos.x, pos.y);
         zoom     = camera.zoom;
         rotation = camera.rotation;
         target;
         viewport = camera.viewport;
       }))
```

**Key Points**:
- Collectors are written by the game (not by eon_engine, not by backends)
- Render_graph_collector is a parallel executor — no phases, no ordering, just run everything concurrently
- Render_graph_collector is backend-agnostic (no knowledge of rendering techniques)

## 6. Rendering_backend

### 6.1 Purpose

The `Rendering_backend` is the only component that knows how to render. It receives a `Render_graph` (already populated by the Render_graph_collector) and produces a render result. The backend has complete autonomy over rendering decisions.

### 6.2 Design

```ocaml
(* rendering_result.mli *)

(** Error type using polymorphic variants for extensibility. *)
type error = [
  | `Texture_not_found of string
  | `Shader_compile_error of string * string  (* shader name, error message *)
  | `Invalid_render_graph of string
  | `Backend_error of string
  | `Custom_error of string * string  (* custom error with context *)
]

(** Result type that all backends must return. *)
type t = {
  errors : error list;
  metadata : (string * string) list;  (* key-value pairs for metadata *)
}

val empty : t
val with_error : t -> error -> t
val with_metadata : t -> string -> string -> t
val has_errors : t -> bool
val error_to_string : error -> string
```

```ocaml
(* rendering_backend.mli *)

module type S = sig
  (** The command type this backend processes.

      Defined as a polymorphic variant that extends the base command set.
      The game writes collectors that emit these commands; the backend
      documents what each extended command does and what data it expects.
  *)
  type command

  (** Load all assets known to [lookup] before the game loop starts.
      The lookup module drives asset discovery; the backend decides how to
      load and store each (logical_id, absolute_path) pair. *)
  val init : (module Asset_lookup.S) -> unit

  (** Render the populated render graph.
      
      Called by the engine loop in the Render slot (after Drain) via Platform.Rendering_backend.
      The graph was built by Render_system during the Tick phase and stored in
      the world data plane.
      
      @param graph The populated render graph
      @return Result containing errors and metadata about the rendering process
  *)
  val render : command Render_graph.t -> dt:float -> Rendering_result.t

  (** Release all GPU resources acquired during [init]. *)
  val shutdown : unit -> unit
end
```

**Wiring collectors**

The game developer adds all collectors explicitly. Collectors that emit only base
commands work with any backend (`[> Render_commands.command]`). Collectors that
emit backend-extended commands are tied to backends that include those variants —
the type system enforces this at the `Render_system.Make` application site:

```ocaml
let render_graph_collector =
  Render_graph_collector.Default.create ()
  |> Render_graph_collector.Default.add_collector Game.collect_sprites
  |> Render_graph_collector.Default.add_collector Game.collect_cameras
  |> Render_graph_collector.Default.add_collector Game.collect_particles
```

If a collector is omitted, those commands never appear in the Render_graph and the
backend silently produces an incomplete frame.

**Key Points**:
- Backend receives an already-populated `Render_graph`
- Backend does not create the pipeline or graph
- Backend has complete control over how to render the graph
- Backend can implement any rendering technique (shaders, batching, culling, etc.)
- **Error Handling**: All errors are returned in the result (no exceptions)
- **Metadata**: Simple key-value string pairs for rendering statistics
- **Polymorphic Variants**: Allow backends to extend error types without changing base interface

### 6.3 Backend Implementation Examples

#### Simple Terminal Backend

```ocaml
module Terminal_backend = struct
  (* Backend uses base commands only *)
  type command = Render_commands.command

  let render graph ~dt:_ =
    let result = Rendering_result.empty in
    try
      let sprite_count = ref 0 in
      let camera_count = ref 0 in
      Render_graph.iter graph (function
        | `Draw_texture { texture_id; source; dest; rotation; tint; _ } ->
            draw_ascii_texture texture_id source dest rotation tint;
            incr sprite_count
        | `Set_camera { position; zoom; rotation; target; viewport } ->
            set_ascii_camera position zoom rotation target viewport;
            incr camera_count
        | `Clear_background color -> clear_ascii color
        | `Draw_text { text; position; _ } -> draw_ascii_text text position
        | `Draw_rect { rect; color; filled; _ } -> draw_ascii_rect rect color filled
        | `Draw_circle { center; radius; color; _ } -> draw_ascii_circle center radius color
        | `Draw_line { start; stop; _ } -> ignore (start, stop)
      );
      result
      |> Rendering_result.with_metadata "backend" "terminal"
      |> Rendering_result.with_metadata "sprites_rendered" (string_of_int !sprite_count)
      |> Rendering_result.with_metadata "cameras_active" (string_of_int !camera_count)
    with
    | Texture_not_found path ->
        Rendering_result.with_error result (`Texture_not_found path)
    | exn ->
        Rendering_result.with_error result (`Backend_error (Printexc.to_string exn))
end
```

#### Custom Backend with Extended Commands

```ocaml
module Custom_backend = struct
  (* Backend extends base commands with its own.
     The game writes collectors that emit these; the backend only consumes them. *)
  type command = [
    | Render_commands.command
    | `Draw_particles of particle_system
    | `Apply_shader of shader
  ]

  let render graph ~dt:_ =
    let result = Rendering_result.empty in
    try
      Render_graph.iter graph (function
        | `Draw_texture data  -> (* handle texture/sprite *)
        | `Set_camera data    -> (* handle camera *)
        | `Clear_background c -> (* clear *)
        | `Draw_text data     -> (* handle text *)
        | `Draw_rect data     -> (* handle rect *)
        | `Draw_circle data   -> (* handle circle *)
        | `Draw_line data     -> (* handle line *)
        | `Draw_particles ps  -> (* handle particles — extended command *)
        | `Apply_shader s     -> (* apply shader — extended command *)
      );
      result
    with exn ->
      Rendering_result.with_error result (`Backend_error (Printexc.to_string exn))
end
```

**Key Points**:
- All backends return `Rendering_result.t`
- Backends process commands using pattern matching (they choose their own strategy)
- Backends can extend the command set using polymorphic variant extension
- Errors are caught and returned in the result (no unhandled exceptions)
- Metadata provides rendering statistics and debugging information

### 6.4 Asset Loading — Backend Responsibility

The `Rendering_backend` is responsible for loading and managing its own assets.
There is no central asset manager in the engine. Each backend owns the GPU handles,
font atlases, and any other resources it needs — the game never sees them.

The game uses stable string identifiers (`texture_id`, `font_id`) as logical names.
The backend resolves those strings to its internal resource handles at render time.

**Asset_lookup.S — the asset discovery seam**

Asset discovery is abstracted behind a signature, consistent with every other
platform seam in the engine:

```ocaml
(* asset_lookup.mli *)

module type S = sig
  (** Iterate all known (logical_id, absolute_path) pairs.
      Called by the backend at init time to preload all assets.
      The backend drives iteration; the lookup module feeds it one pair at a time. *)
  val iter : (string -> string -> unit) -> unit
end

(** Scans [asset_dir] recursively at init time. The relative path from
    [asset_dir] becomes the logical identifier. [asset_dir] is resolved
    relative to the game binary via [Sys.executable_name]. *)
module Dir : sig
  include S
  val create : asset_dir:string -> (module S)
end

(** Always empty — for tests that do not need real assets. *)
module Null : S

(** Hand-maintained list of (logical_id, absolute_path) pairs — for tests
    that need precise control over which assets are visible. *)
module Scripted : sig
  include S
  val create : (string * string) list -> (module S)
end
```

The backend at `init` time calls `iter` and loads whatever the lookup module
provides:

```ocaml
let init (module Lookup : Asset_lookup.S) =
  Lookup.iter (fun logical_id absolute_path ->
    let handle = load_gpu_texture absolute_path in
    Hashtbl.add internal_map logical_id handle)
```

**Production wiring** uses `Asset_lookup.Dir` — the directory structure is the
manifest; drop a file in the right folder and it is immediately available:

```
assets/
  sprites/player.png     → texture_id: "sprites/player.png"
  sprites/tileset.png    → texture_id: "sprites/tileset.png"
  fonts/ui.ttf           → font_id:    "fonts/ui.ttf"
```

```ocaml
let lookup = Asset_lookup.Dir.create ~asset_dir:"assets"
let () = Platform.Rendering_backend.init lookup
```

**Test wiring** uses `Asset_lookup.Null` — backend initialises without touching
the filesystem:

```ocaml
let () = Test_backend.init (module Asset_lookup.Null)
```

Game code uses only the logical key — never a path:

```ocaml
Render_graph.add_world graph (`Draw_texture {
  texture_id = "sprites/player.png";
  (* ... *)
})
```

**Key Points**:
- The engine has no asset manager — each backend owns its resources from `init` to `shutdown`
- `Asset_lookup.S` is a seam like `Input_backend.S` — swappable without touching the backend
- `Dir` is the production default; `Null` and `Scripted` make tests filesystem-free
- `Audio_backend.init` takes its own `Asset_lookup.S`; the two are fully independent
- Hot reloading and streaming can be layered on top later without changing the interface —
  a coordinator system sets a `needs_reload` flag on the relevant component, the collector
  propagates it into the command, and the backend reloads from disk when it sees the flag
- GC-style eviction is a natural backend implementation option — the backend tracks
  `last_used_frame` per asset and evicts anything not seen in the graph for N frames;
  zone transitions become automatic with no explicit load/unload calls from game code;
  revisit when implementing `eon_raylib`

### 7.1 Purpose

The `Render_system` is a standard ECS system that:
1. Overwrites the Render_graph resource in the world data plane with a fresh empty graph
2. Runs the Render_graph_collector (collectors extract rendering data from entities)
3. Stores the populated Render_graph back into the world data plane

The Render_system **never calls the backend**. It only builds and stores the graph.
Platform.Rendering_backend.render is called by the engine loop in the Render slot (after Drain).

### 7.2 Design

```ocaml
(* render_system.mli *)

(** Functor that creates a render system bound to a specific command type.
    
    The functor binds the pipeline's command type at construction time,
    ensuring the stored Render_graph command type matches Platform.Rendering_backend.command.
    
    @param B The backend module (must implement Rendering_backend.S)
*)
module Make (B : Rendering_backend.S) : sig
  (** Create a render system.
      
      Each frame the system:
      1. Overwrites the Render_graph resource with a fresh empty graph
      2. Runs the Render_graph_collector (collectors populate the graph)
      3. Stores the populated graph back into the world data plane
      
      The graph is always overwritten — no double-buffering.
      
      @param render_graph_collector Pipeline configured with collectors
      @return ECS system that builds and stores the Render_graph
  *)
  val make : render_graph_collector:B.command Render_graph_collector.t -> Eon_engine.System.Default.t
end
```

**Key Architecture**:
- Render_system is purely a graph-builder — no backend dependency at runtime
- The world data plane (resource store) is the handoff between Tick and Render
- the engine loop owns the `Platform.Rendering_backend.render` call; `eon_ecs` is clean of all rendering concerns

### 7.3 Integration with ECS Pipeline

```ocaml
(* Register collectors — no phases, no ordering; all run in parallel *)
let render_graph_collector =
  Render_graph_collector.Default.create ()
  |> Render_graph_collector.Default.add_collector Game.collect_sprites
  |> Render_graph_collector.Default.add_collector Game.collect_cameras
  |> Render_graph_collector.Default.add_collector Game.collect_particles

(* Create render system — always via Platform.Rendering_backend, not the backend module directly *)
module My_render_system = Render_system.Make(My_platform.Rendering_backend)
let render_system = My_render_system.make ~render_graph_collector

(* Add to ECS pipeline *)
let ecs_pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Render
  |> Pipeline.add_system `Render render_system
```

### 7.4 System Execution Flow

When the Render_system runs (during ECS Pipeline Tick phase):

```
Render_system.update world dt:
1. graph = Render_graph.create ()                    (* fresh graph, discards previous *)
2. World.set_data world `Render_graph graph           (* store mutable ref in data plane *)
3. Render_graph_collector.collect render_graph_collector (World.readonly world) graph
   - Collectors query world state and add commands to graph (mutates graph in place)
   - Commands are polymorphic variants (extensible by backend)
4. Return unit
   (graph remains in data plane until next frame overwrites it)

Platform.Rendering_backend.render (called by engine loop in Render slot, after Drain):
1. graph = World.get_data world `Render_graph
2. result = Platform.Rendering_backend.render graph ~dt
3. Log errors; store metadata
```

### 7.5 Loop Integration

The `eon_ecs` loop carries no renderer — it is `collect → tick → drain` only.
The render call happens in the `eon_engine` loop; `Loop.Make` internally derives
the renderer from `Platform.Rendering_backend`. Game code only provides the
platform:

```ocaml
module My_platform : Platform.S = struct
  type t = [ `My_platform ]
  module Rendering_backend = My_render_backend
  module Input_backend  = My_input_backend
end

module Loop = Eon_engine.Loop.Make
  (Eon_ecs.Clock.Mtime)
  (Engine_progress)
  (My_platform)
  (Eon_engine.Loop_buses)
```

The engine loop reads the `Render_graph` from the world data plane, calls
`Platform.Rendering_backend.render`, and handles `Rendering_result.t` (logging
errors). `eon_ecs` is entirely free of rendering concerns.

## 8. Platform.S Integration

### 8.1 Overview

`Platform.S` currently carries only `Input_backend`. Implementing the rendering
layer requires adding `Rendering_backend` — named to match `Input_backend`. The
game developer names their backend exactly once, in their `Platform.S`
implementation. The engine loop reads the graph and calls the backend directly —
no adapter module in between.

### 8.2 Extended Platform.S

```ocaml
(* platform.mli — target state after rendering layer is implemented *)
module type S = sig
  type t
  module Rendering_backend : Rendering_backend.S
  module Input_backend  : Input_backend.S
end
```

`Platform.Headless` gains a null render backend for servers, CI, and tests:

```ocaml
module Headless = struct
  type t = [ `Headless ]
  module Rendering_backend = Rendering_backend.Null
  module Input_backend  = Input_backend.Null
end
```

A real platform module names the backend once — no separate functor application:

```ocaml
module Raylib_platform : Platform.S = struct
  type t = [ `Raylib ]
  module Rendering_backend = Raylib_render_backend
  module Input_backend  = Raylib_input_backend
end
```

### 8.3 Render_system.Make — the only backend functor application

The game wires the backend into the render system via `Platform.Rendering_backend`,
not by naming the backend module independently:

```ocaml
module My_render_system = Render_system.Make(Raylib_platform.Rendering_backend)
let render_system = My_render_system.make ~render_graph_collector
```

This is the only place in game code where the backend functor is applied. The
type system ensures the `render_graph_collector` command type matches the backend's
command type at this point.

### 8.4 Loop.Make — render call after drain

No adapter module is needed. `Loop.Make` reads the graph from the world data
plane and calls `Platform.Rendering_backend.render` directly:

```ocaml
let step ~progress ~world ~last_time ~now ~should_continue =
  let raw = Platform.Input_backend.collect () in
  Raw_input_frame.set world raw;
  Buses.collect ();
  let dt = now -. last_time in
  let world = Progress.tick progress ~world ~dt in
  Buses.drain ();
  (match World.get_data world `Render_graph with
   | None -> ()   (* first frame only — Render_system has not run yet *)
   | Some (graph : Platform.Rendering_backend.command Render_graph.t) ->
       let result = Platform.Rendering_backend.render graph ~dt in
       if Rendering_result.has_errors result then
         List.iter
           (fun e -> Printf.eprintf "[renderer] %s\n" (Rendering_result.error_to_string e))
           result.errors);
  let continue = should_continue world in
  (world, now, continue)
```

Frame order:

```
1. Platform.Input_backend.collect () — poll backend; write Raw_input_frame
2. Buses.collect — Signals → Events → Commands
3. Progress.tick — all systems run, including Render_system:
     Render_system clears Render_graph, runs Render_graph_collector, stores graph
4. Buses.drain — Signals → Commands → Events
5. Platform.Rendering_backend.render graph ~dt — reads Render_graph, calls backend
```

`eon_ecs` Loop.Make remains `collect → tick → drain` only — it never grows a
render slot. The render call lives exclusively in `eon_engine` Loop.Make.

## 9. Component Integration

### 9.1 Rendering Components

The rendering layer integrates with existing rendering components:

**Sprite Component** (`components/sprite.mli`):
```ocaml
type t = {
  texture_id : string;
  layer      : int;
  flip_x     : bool;
  flip_y     : bool;
}
```

**Animation Component** (`components/animation.mli`):
```ocaml
type t = {
  clip    : string;
  frame   : int;
  speed   : float;
  playing : bool;
}
```

**Camera Component** (`components/camera.mli`):
```ocaml
type t = {
  zoom       : float;
  viewport_w : float;
  viewport_h : float;
  near       : float;
  far        : float;
}
```

### 9.2 Query Patterns

Game collectors use the query builder to find renderable entities and emit base
commands. The game writes these — the engine has no opinion on component names
or layout:

```ocaml
(* game code *)
let collect_sprites (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Sprite.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let sprite = View.get view (module Components.Sprite) in
       Render_graph.add_world graph (`Draw_texture {
         texture_id = sprite.texture_id;
         source     = sprite.source_rect;
         dest       = { x = pos.x; y = pos.y; w = sprite.w; h = sprite.h };
         rotation   = None;
         origin     = None;
         tint       = None;
         layer      = sprite.layer;
       }))

let collect_cameras (world : World.ro World.t) graph =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Camera.name
  |> Query.iter (fun view ->
       let pos    = View.get view (module Components.Position) in
       let camera = View.get view (module Components.Camera) in
       Render_graph.add_world graph (`Set_camera {
         position = (pos.x, pos.y);
         zoom     = camera.zoom;
         rotation = camera.rotation;
         target   = None;
         viewport = camera.viewport;
       }))
```

Collectors for backend-extended commands (particles, shaders, etc.) follow the
same pattern — query game components, emit backend-specific variants, attach to
an appropriate phase. The backend documents what each extended command expects.

## 10. UI Rendering

UI rendering (microui integration, UI primitive commands, the raygui tradeoff)
is specified in `docs/design/microui_ui_system_design.md`. That work is deferred
until the core rendering layer is implemented.

## 11. Example Usage

**Important Note**: The examples below are illustrative guidelines, not final implementations. They represent ideas that will be iterated over in later phases. The exact API and implementation details may change as the rendering layer evolves.

### 12.1 Basic Usage

```ocaml
(* Create world and register components *)
let world = Eon_ecs.World.create ()
let () = Eon_engine.Components.Engine_components.register_all world

(* Create entities with rendering components *)
let player = World.create_entity world
let () =
  World.add_component world player Components.Position.component { x = 0.0; y = 0.0 };
  World.add_component world player Components.Sprite.component {
    texture_id = "player.png";
    layer      = 10;
    flip_x     = false;
    flip_y     = false;
  }

(* Backend extends base commands with custom commands — documents them, consumes them *)
module My_backend = struct
  type command = [
    | Render_commands.command  (* base commands *)
    | `Apply_shader of shader  (* backend-specific: documented in My_backend docs *)
  ]

  let render graph ~dt:_ =
    let result = Rendering_result.empty in
    (* ... process commands (base + custom) ... *)
    result
end

(* Game writes all collectors — base and backend-extended *)
let collect_shaders (world : World.ro World.t) graph = (* query ShaderComponent, emit `Apply_shader *)

let render_graph_collector =
  Render_graph_collector.Default.create ()
  |> Render_graph_collector.Default.add_collector Game.collect_sprites
  |> Render_graph_collector.Default.add_collector Game.collect_cameras
  |> Render_graph_collector.Default.add_collector collect_shaders

(* Platform — Rendering_backend named once; Loop.Make derives the internal renderer *)
module My_platform : Platform.S = struct
  type t = [ `My_platform ]
  module Rendering_backend = My_backend
  module Input_backend  = My_input_backend
end

(* Render system — uses Platform.Rendering_backend to fix the command type *)
module My_render_system = Render_system.Make(My_platform.Rendering_backend)
let render_system = My_render_system.make ~render_graph_collector

(* Add render system to ECS pipeline *)
let ecs_pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Render
  |> Pipeline.add_system `Render render_system

module Loop = Eon_engine.Loop.Make
  (Eon_ecs.Clock.Mtime)
  (Engine_progress)
  (My_platform)
  (Eon_engine.Loop_buses)

let () =
  let progress = Engine_progress.create ~mode:Progress.Variable pipeline in
  Loop.run ~progress ~world ~should_continue:(fun _ -> true) ()
```

### 12.2 Custom Backend

```ocaml
module Custom_backend = struct
  (* Backend uses base commands only *)
  type command = Render_commands.command

  (* render is called by the engine loop via Platform.Rendering_backend in the Render slot (after Drain) *)
  let render graph ~dt:_ =
    let result = Rendering_result.empty in
    try
      let texture_count = ref 0 in
      Render_graph.iter graph (function
        | `Clear_background color          -> clear color
        | `Set_camera { position; zoom; rotation; target; viewport } ->
            set_camera position zoom rotation target viewport
        | `Draw_texture { texture_id; source; dest; rotation; tint; _ } ->
            draw_texture texture_id source dest rotation tint;
            incr texture_count
        | `Draw_text { text; position; font_id; size; color; _ } ->
            draw_text text position font_id size color
        | `Draw_rect { rect; color; filled; _ } -> draw_rect rect color filled
        | `Draw_circle { center; radius; color; filled; _ } -> draw_circle center radius color filled
        | `Draw_line { start; stop; thickness; color; _ } -> draw_line start stop thickness color
      );
      Rendering_result.with_metadata result "textures_rendered"
        (string_of_int !texture_count)
    with exn ->
      Rendering_result.with_error result (`Backend_error (Printexc.to_string exn))
end
```

**Key Points**:
- Render_graph contains rendering commands (polymorphic variants); no entity references
- `Platform.Rendering_backend.render` is called only by the engine loop in the Render slot (after drain)
- Render_system only builds and stores the graph — it never calls the backend
- Backends can extend the command set using polymorphic variant inclusion
- The game writes collectors for extended commands the same way it writes collectors for base commands

## 12. Conclusion

The rendering layer provides a clean separation of concerns:
- **Engine**: Infrastructure, base command vocabulary, collector type
- **Render_graph_collector**: Phase-based collector executor (mirrors ECS Pipeline)
- **Render_system**: ECS system that drives the pipeline each tick and stores the graph in the world data plane
- **eon_engine Loop.Make**: Internally reads the graph and calls `Platform.Rendering_backend.render` after drain
- **Platform.Rendering_backend**: Has complete control over how to render the graph

**Frame contract**:
- Collect: Signals → Events → Commands
- Tick: All systems run (including Render_system — clears graph, runs pipeline, stores graph)
- Drain: Signals → Commands → Events
- Render: engine loop reads Render_graph from data plane, calls `Platform.Rendering_backend.render`

`eon_ecs` Loop carries no renderer — it is `collect → tick → drain` only. The Render slot is an `eon_engine` concern exclusively.

**Render_system should run after all other systems** to ensure world state is fully updated before collecting rendering data.

**Render_graph handoff**:
- Overwritten every frame — no double-buffering needed
- Safe because the Render slot always consumes the graph written in the same Tick
- Render_system never calls the backend; the engine loop never touches the ECS pipeline

**Backend naming**:
- The game names `Platform.Rendering_backend` exactly once, in its `Platform.S` implementation
- `Render_system.Make(My_platform.Rendering_backend)` is the only functor application in game code
- `Loop.Make` calls `Platform.Rendering_backend.render` directly — no adapter in between

**Command-Based Design**:
- **Base commands**: Backend-agnostic; defined in eon_engine; any backend can consume them
- **Game collectors**: Written by the game for all commands — base and backend-extended alike
- **Backend extension**: Backends extend base commands via polymorphic variant inclusion and document each extended command
- **Type safety**: `Render_system.Make(Platform.Rendering_backend)` fixes the command type; mismatched collectors are a compile error

**Decoupling Architecture**:
- eon_engine provides: Render_graph, Render_graph_collector, Render_system, base command vocabulary, collector type
- Platform.Rendering_backend provides: Extended command type and `render` logic
- Game provides: All collectors; the `Platform.S` implementation; the `render_graph_collector`

**Note**: This design document provides architectural guidelines and implementation ideas. The exact API and implementation details will be refined during implementation phases.

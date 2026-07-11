# eon-engine — Game Engine Layer

Eon Engine builds on top of `eon-ecs` and adds:

- **Typed component descriptors** — no more string-keyed lookups in game code
- **Capability-typed world** — phantom types (`ro`/`rw`) prevent writes from parallel systems at compile time
- **Query builder** — composable filters with a typed `View` cursor
- **Parallel pipeline** — `Parallel` systems run concurrently via `Executor`; `Exclusive` systems run sequentially after
- **Built-in components** — `Position`, `Velocity`, `Rotation`, `Scale`, `Sprite`, `Animation`, `Camera`, `Collider`, `Tag`
- **Rendering layer** — backend-agnostic `Render_commands`/`Render_stream`, phase-ordered `Render_stream_collector`, and a `Rendering_backend.S` seam that decouples the ECS tick from the GPU
- **Transform hierarchy and lifecycle** — optional `Transform_system` (DFS world-transform propagation) and `Lifecycle_system` (`` `Destroy_entity `` with hierarchy-aware cascade)
- **Prefab loading** — format-agnostic `Prefab.Make(Source)(Document_shape)`, with a batteries-included EDN instantiation (`Prefab_edn`) built on `eon-edn`

## Quick start

```ocaml
open Eon_engine

(* 1. Alias the default stack *)
module System   = System.Default
module Pipeline = Pipeline.Default
module Progress = Progress
module Loop     = Loop

(* 2. Create world and register built-in components *)
let world = World.create ()
let ()    = Components.Engine_components.register_all world

(* 3. Define a component for game-specific data *)
let health : int Components.t = component "Health"
let () = ignore (World.register world health)

(* 4. Spawn an entity *)
let player = World.create_entity world
let () =
  World.add_component world player Components.Position.component { x = 0.0; y = 0.0 };
  World.add_component world player Components.Velocity.component { dx = 1.0; dy = 0.5 };
  World.add_component world player health 100

(* 5. Define a parallel system (read-only world) *)
let movement_system =
  System.make
    (Parallel (fun world dt ->
      Query.from world
      |> Query.having Components.Position.name
      |> Query.having Components.Velocity.name
      |> Query.iter (fun view ->
           let pos = View.get view (module Components.Position) in
           let vel = View.get view (module Components.Velocity) in
           ignore (pos.x +. vel.dx *. dt, pos.y +. vel.dy *. dt))))
    ~kind:`Variable
    ()

(* 6. Build a pipeline *)
let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Gameplay
  |> Pipeline.add_system `Gameplay movement_system

(* 7. Build loop and run *)
module Engine_progress = Progress.Make(Pipeline.Default)
module Engine_loop =
  Loop.Make(Eon_ecs.Clock.Mtime)(Engine_progress)(Platform.Headless)(Loop_buses)

let progress = Engine_progress.create ~mode:Engine_progress.Variable pipeline
let _world =
  Engine_loop.run ~progress ~world ~should_continue:(fun _w -> false) ()
```

## Core concepts

### World capabilities

`Eon_engine.World` carries a phantom type parameter — `'perm World.t` —
that enforces read/write discipline at compile time:

- `rw World.t` — full access; returned by `World.create` and held by the loop
- `ro World.t` — read-only view; obtained via `World.readonly`; passed to `Parallel` system updates

Write operations (`create_entity`, `add_component`, `set_component`, …)
are typed to accept only `rw World.t`. Parallel systems receive
`ro World.t` and cannot accidentally mutate shared state.

```ocaml
let world : World.rw World.t = World.create ()
let ro    : World.ro World.t = World.readonly world

(* Read operations accept any capability *)
let alive = World.is_alive ro player

(* Write operations require rw — this would be a type error with [ro] *)
let _e = World.create_entity world
```

### Component descriptors

Components are identified by a typed descriptor value rather than raw
strings. The descriptor carries the value type as a phantom parameter,
eliminating `Obj.magic` at the engine API boundary.

```ocaml
(* Define a descriptor once, typically in a dedicated module *)
let health : int Components.t = Eon_engine.component "Health"

(* Register it with the world before use *)
let _ = World.register world health

(* Use the descriptor for all component operations *)
World.add_component world entity health 100;
let hp = World.get_component world entity health  (* : int option *)
```

### Built-in components

The engine ships with `Eon_engine.Components`, which exposes typed
component modules:

| Module | Type | Description |
|---|---|---|
| `Components.Local_transform` | `{position; rotation; scale}` | Transform relative to parent (or world origin) |
| `Components.World_transform` | `{position; rotation; scale}` | Fully composed world-space transform — read-only |
| `Components.Parent` | `{entity : entity_id}` | Parent entity reference; absence = root |
| `Components.Children` | `{entities : entity_id list}` | Engine-maintained child entity list |
| `Components.Velocity` | `{dx: float; dy: float}` | 2D velocity |
| `Components.Sprite` | `Sprite.t` | Rendering info |
| `Components.Animation` | `Animation.t` | Sprite animation |
| `Components.Camera` | `Camera.t` | Camera projection |
| `Components.Collider` | `Collider.t` | Collision shape |
| `Components.Tag` | `string` | String marker |

Register all of them at once with
`Components.Engine_components.register_all world`.

To extend with game-specific components:

```ocaml
module Game_components = struct
  include Components.Engine_components

  let mana : int Components.t = component "Mana"
  let xp   : int Components.t = component "XP"

  let register_all world =
    Components.Engine_components.register_all world;
    ignore (World.register world mana);
    ignore (World.register world xp)
end
```

### Query builder

`Eon_engine.Query` is a composable builder that accepts both `ro` and `rw`
worlds. Filters narrow the entity set; `iter` executes the query and
passes a typed `Eon_engine.View` cursor per matching entity.

```ocaml
Query.from world
|> Query.having     Components.Position.name   (* must have Position *)
|> Query.having     Components.Velocity.name   (* must have Velocity *)
|> Query.not_having Components.Tag.name        (* must not have Tag  *)
|> Query.iter (fun view ->
     let entity = View.entity view in
     let pos    = View.get view (module Components.Position) in
     let vel    = View.get view (module Components.Velocity) in
     ignore (entity, pos, vel))
```

Use `View.get` for components you required in the query (raises on
absent — treat as programmer error). Use `View.get_opt` for optional
components. Use `Query.count` instead of `iter` when you only need the
entity count.

### Parallel and exclusive systems

Engine systems declare their world-access pattern up front:

- **`Parallel`** — `update` receives `World.ro World.t`; the pipeline dispatches it concurrently with other parallel systems in the same phase. Safe for queries and reads.
- **`Exclusive`** — `update` receives `World.rw World.t`; runs sequentially *after* all parallel systems in the phase have completed. Structural mutations — spawning, destroying entities, adding or removing components — belong in `update` here; that is the entire reason `Exclusive` exists.

#### Module-based style (recommended)

Each system lives in its own file and satisfies either
`Eon_engine.System.Parallel_def` or `Eon_engine.System.Exclusive_def`.
Both signatures require:

- `type signal`, `type event`, `type command` — the message payload types for the three buses
- `on_signal`, `on_event`, `on_command` — reactive handlers; implement as `let on_* _ _ = ()` if unused
- `update` — `World.ro World.t` for `Parallel_def`, `World.rw World.t` for `Exclusive_def`

**Parallel system — queries in `update`, writes via emitted commands:**

Parallel systems cannot write directly in `update` — the world is `ro`
there. Instead they compute new state and emit a command; the
`on_command` handler applies the mutation with `rw` access during the
`drain` phase.

```ocaml
(* systems/movement.ml — satisfies System.Parallel_def *)
open Eon_engine

type signal  = unit
type event   = unit
type command = [ `Move_to of Eon_ecs.Entity_id.t * float * float ]

let on_signal  _ _ = ()
let on_event   _ _ = ()

(* on_command runs sequentially during drain with full rw access *)
let on_command (world : World.rw World.t) = function
  | `Move_to (entity, x, y) ->
    World.set_component world entity Components.Position.component { x; y }

(* update is ro — compute new positions and emit, never write directly *)
let update (world : World.ro World.t) dt =
  let bus = Buses.Default.commands () in
  Query.from world
  |> Query.having Components.Position.name
  |> Query.having Components.Velocity.name
  |> Query.iter (fun view ->
       let e   = View.entity view in
       let pos = View.get view (module Components.Position) in
       let vel = View.get view (module Components.Velocity) in
       Commands.emit bus (`Move_to (e, pos.x +. vel.dx *. dt,
                                       pos.y +. vel.dy *. dt)))
```

**Exclusive system — mutations happen in `update`, which has full `rw` access:**

```ocaml
(* systems/cleanup.ml — satisfies System.Exclusive_def *)
open Eon_engine

type signal  = unit
type event   = unit
type command = unit

let on_signal  _ _ = ()
let on_event   _ _ = ()
let on_command _ _ = ()

(* update receives rw — spawn, destroy, add/remove components freely *)
let update (world : World.rw World.t) _dt =
  Query.from world
  |> Query.having Components.Tag.name
  |> Query.iter (fun view ->
       let e   = View.entity view in
       let tag = View.get view (module Components.Tag) in
       if tag = "dead" then World.destroy_entity world e)
```

**Assemble and add to the pipeline:**

```ocaml
let pipeline =
  Pipeline.Default.create ()
  |> Pipeline.Default.add_phase `Gameplay
  |> Pipeline.Default.add_system `Gameplay (System.make_parallel  (module Movement))
  |> Pipeline.Default.add_system `Gameplay (System.make_exclusive (module Cleanup))
  (* parallel systems run concurrently first,
     then exclusive systems run with rw access *)
```

#### Systems with reactive bus handlers

Bus handlers always receive `World.rw World.t` regardless of the
system's `Parallel`/`Exclusive` dispatch — handlers run sequentially
during the `drain` phase, never concurrently. Declare the payload types
and implement the handler:

```ocaml
(* systems/combat.ml — parallel update, reactive command handler *)
open Eon_engine

type signal  = unit
type event   = [ `Enemy_died of Eon_ecs.Entity_id.t ]
type command = [ `Apply_damage of Eon_ecs.Entity_id.t * int ]

let on_signal _ _ = ()

let on_event (world : World.rw World.t) = function
  | `Enemy_died e -> World.destroy_entity world e

let on_command (world : World.rw World.t) = function
  | `Apply_damage (e, amount) ->
    (match World.get_component world e health_desc with
     | Some hp -> World.set_component world e health_desc (hp - amount)
     | None    -> ())

let update (world : World.ro World.t) _dt =
  Query.from world
  |> Query.having Components.Position.name
  |> Query.iter (fun _view -> ())
```

#### Inline closure style (for simple or one-off systems)

For throwaway or test systems, skip the module file and pass closures
directly:

```ocaml
let debug_system =
  System.Default.make
    (Parallel (fun world _dt ->
      let n = World.count_entities world in
      ignore n))
    ~kind:`Variable
    ()

let reset_system =
  System.Default.make
    (Exclusive (fun world _dt ->
      ignore (World.create_entity world)))
    ~kind:`Variable
    ()
```

### Executor

`Eon_engine.Executor` is the threading-substrate seam. Swap it to change
parallelism without touching any system code:

```ocaml
(* Sequential: single-threaded, same as eon_ecs core — good for testing *)
module Seq_pipeline = Pipeline.Make
  (System.Make(Eon_ecs.System.Make(Signals)(Events)(Commands)))
  (Executor.Sequential)
  (Buses.Default)

(* Parallel: OCaml 5 Domain pool — true concurrent dispatch *)
module Par_pipeline = Pipeline.Make
  (System.Make(Eon_ecs.System.Make(Signals)(Events)(Commands)))
  (Executor.Domain_pool.Make(struct
     let size = Executor.Domain_pool.recommended_size ()
   end))
  (Buses.Default)
```

`Executor.run_all` is always synchronous — it returns only after every
job finishes, giving automatic phase barriers with no extra
synchronisation code.

### Buses

The engine buses (`Signals`, `Events`, `Commands`) are mutex-wrapped
versions of the core buses, safe to `emit` from parallel system threads.
Their collect/drain semantics are identical to `eon_ecs`:

| Module | Semantics |
|---|---|
| `Signals`  | Same-frame delivery (`drain = collect`) |
| `Events`   | Next-frame delivery (double-buffer swap) |
| `Commands` | Same-frame delivery, intended for mutations |

### Transform hierarchy and entity lifecycle

Two optional, independent systems for spatial hierarchy and controlled
entity destruction. Use one, both, or neither — they share a command bus
but have no module dependency on each other.

| System | Responsibility |
|---|---|
| `Transform_system` | DFS world-transform propagation; `` `Reparent `` command handling |
| `Lifecycle_system` | `` `Destroy_entity `` command; guards with `World.is_alive` |

Four components make up the hierarchy (`Local_transform`, `World_transform`,
`Parent`, `Children`), all registered by
`Components.Engine_components.register_all`. `Local_transform` is what
game code writes; `World_transform` is the derived, read-only result —
never write it or `Children` directly, `Transform_system` owns both.

**Registration order matters.** Both buses dispatch handlers in pipeline
registration order (FIFO), so `Transform_system` must be registered
*before* `Lifecycle_system` — its handler detaches children from the
hierarchy before `Lifecycle_system` removes the entity:

```ocaml
open Eon_engine

let lifecycle  = Lifecycle_system.Default.make ()
let transforms = Transform_system.Default.make ()

(* IMPORTANT: Transform_system before Lifecycle_system — see above *)
let pipeline =
  Pipeline.Default.create ()
  |> Pipeline.Default.add_phase `Lifecycle
  |> Pipeline.Default.add_system `Lifecycle lifecycle
  |> Pipeline.Default.add_phase `Transform
  |> Pipeline.Default.add_system `Transform transforms
```

Hierarchy mutations go through commands, not direct component writes:
`` `Reparent `` (attach/detach — pass `new_parent = None` to detach) and
`` `Destroy_entity `` (safe to emit twice; guarded by `is_alive`).
`Transform_hierarchy.attach` is a synchronous helper for building the
hierarchy *before* the loop starts (setup time only — mid-simulation use
`` `Reparent `` instead, so `Transform_system` can keep `Parent`/`Children`
consistent). `Transform_hierarchy.despawn_recursive` walks a subtree
depth-first and emits `` `Destroy_entity `` for every node, deepest first:

```ocaml
(* In a Parallel system's update — reads world (ro), emits commands *)
let update (world : World.ro World.t) _dt =
  let emit = Single_bus.emit (Buses.Default.commands ()) in
  Transform_hierarchy.despawn_recursive world root_entity ~emit
```

**Extending `Lifecycle_system`.** `Lifecycle_system.Default.make` accepts
an optional `~on_command` callback that fires *before* the built-in
`` `Destroy_entity `` handler — the entity is still alive when it runs, so
its components are still readable. The callback receives the full command
type, not just `` `Destroy_entity ``, which makes `Lifecycle_system` a
natural extensible lifecycle hub — spawn logic, audio teardown, logging,
particle despawn, all in one place with correct ordering relative to
`Transform_system`:

```ocaml
let lifecycle = Lifecycle_system.Default.make
  ~on_command:(fun world cmd ->
    match cmd with
    | `Spawn { position; prefab } -> Prefab.instantiate world ~position prefab
    | `Destroy_entity entity      -> Fx.play_death_effect world entity
    | _ -> ()
  )
  ()
```

Either system can be omitted independently — `Transform_system` alone
propagates transforms with no lifecycle handling; `Lifecycle_system` alone
destroys entities with no hierarchy cleanup (fine if entities have no
hierarchy components). Full deep dive, including manual cascade
destruction without either system:
`eon_engine/doc/transform_and_lifecycle.mld`.

### Rendering

This is the most order-sensitive part of the engine, so it's worth
walking through in full. The rendering layer decouples the ECS tick from
the GPU: during a tick, game systems write backend-agnostic commands into
a `Render_stream`; after the tick, the loop hands that stream to a
`Rendering_backend.S` implementation which produces pixels. The two sides
never call each other directly. Frame order:

```
collect  →  tick (Render_system clears + fills stream)
         →  drain
         →  Platform.Rendering_backend.render stream ~dt
```

**`Render_commands`** defines seven backend-agnostic commands covering a
complete 2D game: `` `Clear_background ``, `` `Set_camera ``,
`` `Draw_texture ``, `` `Draw_rect ``, `` `Draw_text ``, `` `Draw_line ``,
`` `Draw_circle ``. Backends that need more extend the type via
polymorphic variant inclusion — the engine never sees the extended type:

```ocaml
type command = [
  | Render_commands.command   (* includes all seven base commands *)
  | `Apply_shader   of shader
  | `Draw_particles of particle_system
]
```

**`Render_stream`** holds two independent command lists: **world space**
(camera-relative — `` `Set_camera `` followed by draw commands, repeated
per camera) and **screen space** (fixed regardless of camera — HUD,
damage numbers, overlays). It's a reusable buffer: `Render_stream.clear`
resets both lists but retains backing-array capacity, so a steady-state
frame allocates nothing.

**`Render_stream_collector`** organises collectors into named phases,
ordered with `~after` — the same model as `Pipeline.before`/`after`. A
collector has type `World.ro World.t -> 'command Render_stream.t -> unit`
(read-only world access enforced by the type system). Collectors within
and across phases run **sequentially in phase, then addition, order** —
this is intentional: concurrent collectors writing to the same stream
would interleave non-deterministically. For parallel collection, collect
into per-collector private streams and merge them in a sequential pass.

```ocaml
let render_collector =
  Render_stream_collector.create ()
  |> Render_stream_collector.add_phase `Camera
  |> Render_stream_collector.add_phase `World  ~after:`Camera
  |> Render_stream_collector.add_phase `Screen ~after:`World
  |> Render_stream_collector.add_collector `Camera collect_camera
  |> Render_stream_collector.add_collector `World  collect_sprites
  |> Render_stream_collector.add_collector `Screen collect_hud
```

Multi-camera setups just add more `~after`-chained phase pairs — a
minimap is two more `add_phase` lines, no central list to edit. The
backend then iterates the world-space list linearly and tracks camera
state as it goes, calling `begin_mode_2d`/`end_mode_2d` around the
commands between each `` `Set_camera ``.

**`Render_system.Make`** produces a standard ECS system that (1) clears
the `Render_stream` at the start of each tick, (2) calls
`Render_stream_collector.collect` to repopulate it, (3) stores the stream
reference in the world data plane under `` `Render_stream ``. It never
calls the backend itself — add it to whichever pipeline phase runs last:

```ocaml
module My_render_system = Render_system.Make(Rendering_backend.Null)
let render_system = My_render_system.make ~render_stream_collector:render_collector

let pipeline =
  Pipeline.Default.create ()
  |> Pipeline.Default.add_phase `Gameplay
  |> Pipeline.Default.add_phase `Render   ~after:`Gameplay
  |> Pipeline.Default.add_system `Gameplay movement_system
  |> Pipeline.Default.add_system `Render   render_system
```

`Render_system` is optional — the loop only looks for a `Render_stream`
value under `` `Render_stream `` in the world data plane, and doesn't care
how it got there; a headless simulation with no `Render_system`
registered silently skips the render step.

**`Rendering_backend.S`** is the seam a platform library (raylib, etc.)
implements. It receives the populated stream once per frame, after
`drain`, and has full autonomy over batching, layer sorting, and GPU
dispatch — the engine imposes no structure beyond "iterate the stream".
It returns `Rendering_result.t` for non-fatal errors (missing textures,
unknown fonts); the loop logs those automatically, while fatal errors
(GPU lost, OOM) should just raise. `Rendering_backend.Null` discards
every command and is wired into `Platform.Headless` for tests and CI.

Full deep dive — color, all seven commands, multi-camera walkthrough, a
skeleton raylib backend, asset loading conventions, and non-fatal error
handling: `eon_engine/doc/rendering.mld`.

### Input

The engine's input job is minimal: poll the platform backend once per
frame and store the result as a `Eon_engine.Raw_input_frame` world
resource. Game systems read it via `Raw_input_frame.get world`.
Everything above that — action mapping, binding tables, event dispatch —
is a game-layer concern.

**Key types** are backend-agnostic enums. Backends map native codes to these:

| Module | Description |
|---|---|
| `Eon_engine.Key` | Keyboard keys |
| `Eon_engine.Mouse_button` | Mouse buttons |
| `Eon_engine.Gamepad_button` | Gamepad buttons |

Each has a `Set` submodule (`Key.Set`, `Mouse_button.Set`,
`Gamepad_button.Set`) for efficient membership tests.

**Raw_input_frame** is an immutable snapshot written before
`Buses.collect` runs. Fields include pressed/released/down sets, mouse
position and delta, gamepad state, scroll delta, text input from the OS
IME, and a timestamped event list:

```ocaml
(* In an Exclusive system's update: *)
let update (world : World.rw World.t) _dt =
  match Raw_input_frame.get world with
  | None -> ()
  | Some frame ->
    if Key.Set.mem Key.Space frame.Raw_input_frame.keys_pressed then
      (* space was pressed this frame — emit a jump command *)
      ()
```

**Input_backend.S** is the seam for platform-specific input polling. Two
built-in implementations ship with the engine:

- `Eon_engine.Input_backend.Null` — always returns `Raw_input_frame.empty`
- `Eon_engine.Input_backend.Scripted` — replays a pre-set list of frames; use this in tests to feed deterministic input without a window

```ocaml
Input_backend.Scripted.set_frames [
  { Raw_input_frame.empty with
    keys_pressed = Key.Set.singleton Key.Space };
  Raw_input_frame.empty;
]
```

### Platform

`Eon_engine.Platform.S` is the compile-time seam passed to `Loop.Make`.
It bundles `Input_backend`, `Audio_backend`, and `Rendering_backend`.
Game binaries supply a concrete platform (e.g. a raylib platform);
servers and tests use `Eon_engine.Platform.Headless`:

```ocaml
(* Headless: null input, audio, and rendering — for tests and servers *)
module Engine_loop =
  Loop.Make
    (Eon_ecs.Clock.Mtime)
    (Engine_progress)
    (Platform.Headless)
    (Loop_buses)

(* Game binary: swap in the real platform *)
module Game_loop =
  Loop.Make
    (Eon_ecs.Clock.Mtime)
    (Engine_progress)
    (Raylib_platform)   (* user-supplied Platform.S *)
    (Loop_buses)
```

### Loop

`Eon_engine.Loop.Make` orchestrates one frame:

1. `Platform.Input_backend.collect ()` — poll backend; result stored as `Raw_input_frame` world resource before any system runs
2. `Buses.collect` — Signals, then Events, then Commands
3. `Progress.tick` — runs the pipeline; `Render_system` (if registered) clears and populates the `Render_stream` during this step
4. `Buses.drain` — Signals, then Commands, then Events
5. `Platform.Audio_backend.submit` — submit accumulated audio commands
6. `Platform.Rendering_backend.render` — consume the `Render_stream` from the world data plane; skipped silently if no stream is present

`Loop.run` calls `init` on all three backends before entering the loop
and their `shutdown` counterparts after it returns.

```ocaml
let final_world =
  Loop.run
    ~progress
    ~world
    ~should_continue:(fun _world -> true)
    ()
```

## Guides

Full odoc tutorials — build with `just open-docs` and browse to
`eon-engine`:

- **Math types** (`doc/math.mld`) — `Vec2`, `Vec2i`, `Rect`, `Circle`, `Transform2D`: construction, common patterns, tile coordinate conversion, spatial queries, and hierarchy transforms.
- **Rendering** (`doc/rendering.mld`) — `Color`, `Render_commands`, `Render_stream`, `Render_stream_collector`, `Render_system`, `Rendering_backend`: command vocabulary, phase-ordered collection, multi-camera setup, backend wiring, and complete loop integration.
- **Transform hierarchy and entity lifecycle** (`doc/transform_and_lifecycle.mld`) — `Local_transform`, `World_transform`, `Parent`, `Children`, `Transform_system`, `Lifecycle_system`, `Transform_hierarchy`: DFS world-transform propagation, reparenting, entity destruction, registration order, and cascade patterns.
- **Prefab loading** (`doc/prefab.mld`) — `Prefab.Make`, `Prefab_edn`, `Prefab_edn_defaults`: using the built-in EDN loader, writing a custom `Component_deserializer`, `:extends`/`:children` conventions, and building a non-EDN instantiation from scratch.

## Build and test

Use `just` from the repo root:

```sh
just build
just run-tests
just test eon_engine/test/test_main.exe
just engine-bench executor
just engine-bench render_stream
just engine-bench prefab
```

## API reference

Full odoc reference: `just open-docs`, then browse to `eon-engine`. The
composition root is `eon_engine/eon_engine.ml`; the public contract is
`eon_engine/eon_engine.mli`.

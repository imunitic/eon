# eon-ecs — Entity Component System

Eon ECS is a minimal, data-oriented ECS library for OCaml 5. It provides
entities, typed component storage, message buses, a system scheduler, and a
fixed/variable-step game loop — all wired together through a default stack
you can use directly or customise via functors.

## Quick start

```ocaml
(* 1. Alias the default stack *)
module World    = Eon_ecs.World
module System   = Eon_ecs.System.Default
module Pipeline = Eon_ecs.Pipeline.Default
module Progress = Eon_ecs.Progress.Default
module Loop     = Eon_ecs.Loop.Default
module Signals  = Eon_ecs.Signals
module Events   = Eon_ecs.Events
module Commands = Eon_ecs.Commands

(* 2. Create world and register components *)
let world = World.create ()
let _pos  = World.register_component world ~name:"Position" ~id:0
let _vel  = World.register_component world ~name:"Velocity" ~id:1

(* 3. Spawn an entity *)
let player = World.create_entity world
let () =
  World.add_component world player ~name:"Position" (0.0, 0.0);
  World.add_component world player ~name:"Velocity" (1.0, 0.5)

(* 4. Define a system *)
let movement =
  System.make
    ~update:(fun world dt ->
      Eon_ecs.Query.iter2 world "Position" "Velocity"
        (fun _entity (px, py) (vx, vy) ->
          ignore (px +. vx *. dt, py +. vy *. dt)))
    ~kind:`Variable
    ()

(* 5. Build a pipeline *)
let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Gameplay
  |> Pipeline.add_system `Gameplay movement

(* 6. Create a progress controller and run *)
let progress = Progress.create ~mode:(Progress.Variable) pipeline
let _world =
  Loop.run
    ~progress
    ~world
    ~should_continue:(fun _world -> false)
    ()
```

## Core concepts

### World

`Eon_ecs.World` is the central mutable state. It owns:

- **Entities** — opaque `Eon_ecs.Entity_id.t` handles with a generation counter to prevent stale-handle reuse.
- **Component storage** — each component type is registered by name and integer id; per-entity values are stored in sparse sets.
- **Data and service stores** — arbitrary values keyed by open polymorphic variants for lightweight dependency injection.

```ocaml
let world = Eon_ecs.World.create () in

(* Register a component type before attaching it to any entity *)
let _hp = Eon_ecs.World.register_component world ~name:"Health" ~id:0 in

let e = Eon_ecs.World.create_entity world in
Eon_ecs.World.add_component world e ~name:"Health" 100;

let hp = Eon_ecs.World.get_component world e ~name:"Health" in
assert (hp = Some 100);

Eon_ecs.World.destroy_entity world e
```

Important: `Eon_ecs.World.get_component` returns `None` if the entity doesn't
have the component, but **raises** if the component name was never
registered. Do not use the exception for control flow.

### Components

Components are plain OCaml values. Register a type with
`Eon_ecs.World.register_component`, then attach instances to entities with
`Eon_ecs.World.add_component`. Use `Eon_ecs.World.set_component` to
overwrite (it promotes to add if the value is absent).

### Queries

`Eon_ecs.Query` iterates entities that own a given intersection of
components. It picks the smallest sparse set as the iteration base and
checks membership in the rest, so queries over rare components are cheap.

```ocaml
(* Iterate every entity that has both Position and Velocity *)
Eon_ecs.Query.iter2 world "Position" "Velocity"
  (fun entity (px, py) (vx, vy) ->
    ignore (entity, px, py, vx, vy))
```

Variants: `Eon_ecs.Query.iter1` through `Eon_ecs.Query.iter4`, and
`Eon_ecs.Query.count` for a count without a callback.

### Buses

Buses carry typed messages between systems. The default stack exposes three:

| Module | Implementation | Delivery |
|---|---|---|
| `Eon_ecs.Signals`  | `Eon_ecs.Bus.Single` | Same frame — `drain = collect` |
| `Eon_ecs.Events`   | `Eon_ecs.Bus.Double` | Next frame — `emit` → next buffer; swap on `drain` |
| `Eon_ecs.Commands` | `Eon_ecs.Bus.Single` | Same frame — world-mutating handlers |

```ocaml
let commands = Eon_ecs.Commands.create () in
Eon_ecs.Commands.on commands (fun `Destroy_all -> ());
Eon_ecs.Commands.emit commands `Destroy_all;
Eon_ecs.Commands.drain commands   (* handler fires here *)
```

Use **Signals** for fan-out notifications where any number of systems may
react. Use **Events** when reactions must be deferred to the next frame.
Use **Commands** when a system knows exactly what mutation to apply.

Multiple handlers subscribed to the same bus fire in **pipeline registration order** — the same order systems run in `update`. A system's
position in the phase graph governs both its `update` execution and its
handler dispatch.

### Systems

A system is built with `Eon_ecs.System.Default.make`. All callbacks are
optional — omit `update` for a handler-only system, omit `on_signal` /
`on_event` / `on_command` for a non-reactive system.

```ocaml
module System = Eon_ecs.System.Default

let physics =
  System.make
    ~update:(fun world dt ->
      Eon_ecs.Query.iter2 world "Position" "Velocity"
        (fun _e (px, py) (vx, vy) ->
          ignore (px +. vx *. dt, py +. vy *. dt)))
    ~kind:`Fixed   (* runs at fixed timestep *)
    ()

let input =
  System.make
    ~on_command:(fun world cmd -> ignore (world, cmd))
    ~kind:`Variable
    ()
```

The `kind` tag determines which phase of the progress controller runs this
system: `` `Fixed `` systems run at a deterministic step size;
`` `Variable `` systems run once per frame.

### Pipelines

`Eon_ecs.Pipeline.Default` holds phases, ordering edges between phases, and
systems assigned to phases. Phases are polymorphic variants — any value
works.

```ocaml
module Pipeline = Eon_ecs.Pipeline.Default

let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Input
  |> Pipeline.add_phase `Physics
  |> Pipeline.add_phase `Render
  |> Pipeline.before ~earlier:`Input  ~later:`Physics
  |> Pipeline.before ~earlier:`Physics ~later:`Render
  |> Pipeline.add_system `Input   input
  |> Pipeline.add_system `Physics physics
```

**Never add phases or ordering edges after the loop starts.** The
topological sort is cached; it only re-runs when phases or edges are
added, not when systems are added.

### Progress controllers

`Eon_ecs.Progress.Default` drives a pipeline at a chosen time mode:

- `Variable` — one tick per frame, `dt` from the clock.
- `Fixed step` — fixed `dt`, multiple ticks per frame to catch up.
- `Hybrid step` — fixed ticks plus one variable tick per frame.

```ocaml
module Progress = Eon_ecs.Progress.Default

let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
```

### Loop

`Eon_ecs.Loop.Default` ties everything together. Frame order is always:

1. `collect` — Signals, then Events, then Commands
2. `Progress.tick` — runs the pipeline
3. `drain` — Signals, then Commands, then Events

The loop carries no renderer — rendering is a `` `Variable `` system in a
`Render` phase, ordered after your simulation phases.

```ocaml
module Loop = Eon_ecs.Loop.Default

let final_world =
  Loop.run
    ~progress
    ~world
    ~should_continue:(fun _world -> true)
    ()
```

Use `Eon_ecs.Loop.Default.step` for manual frame control (e.g. inside an
event loop from an external framework).

## Build and test

Use `just` from the repo root:

```sh
just build
just run-tests
just test eon_ecs/test/test_main.exe
just bench sparse_set
just bench entity_manager
just bench query
just bench world
just bench loop
```

## Example: non-reactive Snake

The repository includes a compact, data-centric Snake example that shows
the canonical ECS shape end to end:

- Source: `eon_ecs/examples/snake_nonreactive.ml`
- Run: `just snake_nonreactive`

Game logic and mutations happen in ECS systems (`input_system`,
`movement_system`, `alive_system`); state is modeled via
components/world data; rendering is fully separated in `Snake_renderer`;
loop timing/orchestration is explicit (`Pipeline` phases with
`Input -> Gameplay` ordering + `Progress.Hybrid` + `Loop.run`).

## API reference

Full odoc reference: `just open-docs`, then browse to `eon-ecs`. The
composition root is `eon_ecs/eon_ecs.ml`; the public contract is
`eon_ecs/eon_ecs.mli`.

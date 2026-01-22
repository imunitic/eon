[![Eon ECS Core CI](https://github.com/imunitic/eon/actions/workflows/ci.yml/badge.svg)](https://github.com/imunitic/eon/actions/workflows/ci.yml)

# Eon ECS

Eon ECS is a minimal, deterministic, backend-agnostic entity-component-system runtime for OCaml.
This repo currently contains:

- `eon_ecs/` (library: `eon-ecs`) - the ECS core.
- `eon_engine/` (library: `eon-engine`) - a stub engine layer that currently only depends on `eon-ecs`.

## Core status and TODOs

- [x] Resource_store (services + data planes) with hashed variant keys.
- [x] Signals, Events, and Commands buses with collect/drain semantics.
- [x] System core + reactive record (register/update/on_* + kind).
- [x] Pipeline with ordered phases and dependency edges.
- [x] Progress controller with Variable, Fixed(step), and Hybrid modes.
- [x] Query helpers: `iter1`, `iter2`, `iter3`, `iter4`, and `count`.
- [x] Loop module with `step` and `run`, plus `Loop.Default` wiring.
- [x] Bechamel benchmarks for Sparse_set, Entity_manager, and Query iter1-4.
- [ ] Optional RenderGraph/Drawable integration (engine layer).
- [ ] Multiple pipelines per world (not built into the core).
- [ ] QCheck property-based tests for core invariants.
- [ ] Benchmarks for `World.set_component/get_component` and `Loop.step`.

## Default stack (Eon_ecs)

The standard entry point is the `Eon_ecs` module, which exposes a default stack:

| Role      | Default Module                 | Notes |
|-----------|--------------------------------|-------|
| World     | `Eon_ecs.World`                | Entities, components, resources, services. |
| Systems   | `Eon_ecs.System.Default`       | Reactive systems wired to default buses. |
| Pipeline  | `Eon_ecs.Pipeline.Default`     | Phase graph over polymorphic variant keys. |
| Progress  | `Eon_ecs.Progress.Default`     | Variable/Fixed/Hybrid modes over `System.kind`. |
| Loop      | `Eon_ecs.Loop.Default`         | Clock + progress + renderer + default buses. |
| Buses     | `Eon_ecs.Signals/Events/Commands` | Single/Double buffer semantics. |

## Quickstart (default modules)

```ocaml
module World    = Eon_ecs.World
module System   = Eon_ecs.System.Default
module Pipeline = Eon_ecs.Pipeline.Default
module Progress = Eon_ecs.Progress.Default
module Query    = Eon_ecs.Query
module Signals  = Eon_ecs.Signals
module Events   = Eon_ecs.Events
module Commands = Eon_ecs.Commands
module Loop     = Eon_ecs.Loop.Default

let world =
  let world = World.create () in
  let signals  = Signals.create ()
  and events   = Events.create ()
  and commands = Commands.create () in
  World.add_service world `Signals  signals;
  World.add_service world `Events   events;
  World.add_service world `Commands commands;
  ignore (World.register_component world ~name:"Position" ~id:0);
  ignore (World.register_component world ~name:"Velocity" ~id:1);
  let entity = World.create_entity world in
  World.add_component world entity ~name:"Position" (0.0, 0.0);
  World.add_component world entity ~name:"Velocity" (1.0, 0.0);
  world

let commands = World.get_service world `Commands |> Option.get

let movement_system =
  System.make_reactive
    ~update:(fun world dt ->
      Query.iter2 world "Position" "Velocity"
        (fun entity (x, y) (vx, vy) ->
          let speed = (vx *. dt, vy *. dt) in
          Commands.emit commands (`Move_player (entity, speed)) ))
    ~on_command:(fun world -> function
        | `Move_player (entity, (dx, dy)) ->
            begin
              match World.get_component world entity ~name:"Position" with
              | Some (x, y) ->
                  World.set_component world entity ~name:"Position" (x +. dx, y +. dy)
              | None -> ()
            end
        | _ -> ())
    ~kind:`Fixed
    ()
  |> System.attach_handlers world

let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Gameplay
  |> Pipeline.add_system `Gameplay movement_system

let () = Pipeline.register_all pipeline world

let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline

let should_continue _world () = true

let _final_world =
  Loop.run
    ~progress
    ~world
    ~should_continue
```

## Message buses

- `Signals` uses `Single_bus` (same-frame delivery).
- `Events` uses `Double_bus` (next-frame delivery).
- `Commands` uses `Single_bus` (same-frame delivery).

Default loop bus order:

1. `collect` Signals -> Events -> Commands
2. `Progress.tick`
3. `drain` Signals -> Commands -> Events
4. Render after drains

The loop orchestrates collect/drain; systems only emit or handle messages.

## Loop

`Eon_ecs.Loop.Make` combines a clock, progress controller, renderer, and bus wiring.
`Eon_ecs.Loop.Default` uses `Clock.Mtime`, `Progress.Default`, a no-op renderer, and
`Loop_default_buses`. The loop exposes:

- `step`: one frame given `last_time` and `now`.
- `run`: repeatedly calls `step` until the continuation predicate returns false.

## Progress

`Eon_ecs.Progress` provides Variable/Fixed/Hybrid modes and runs pipeline systems
filtered by system kind. Custom kind sets are supported via `Make_with_kind`.

## Pipeline

Pipelines define phases, dependencies, and system registration. `run_by_filter` is
used by `Progress` to execute systems matching a given kind.

## World and resources

`World` manages entities, component registration/storage, and a `Resource_store` that
holds services and arbitrary data keyed by open variants (hashed to ints).
Components must be registered before `add_component`/`set_component`.

## Tests and benchmarks

- Alcotest suites cover `Pipeline`, `Progress`, `World`, `System`, `Query`, and `Loop`.
- Bechamel benchmarks live in `eon_ecs/bench/`.

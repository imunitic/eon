[![Eon ECS Core CI](https://github.com/imunitic/eon/actions/workflows/ci.yml/badge.svg)](https://github.com/imunitic/eon/actions/workflows/ci.yml)
[![Coverage (Bisect)](https://github.com/imunitic/eon/actions/workflows/coverage.yml/badge.svg)](https://github.com/imunitic/eon/actions/workflows/coverage.yml)

# Eon ECS

Eon ECS is a minimal, deterministic, backend-agnostic entity-component-system runtime for OCaml.

This repo currently contains:
- `eon_ecs/` (`eon-ecs`): ECS core runtime.
- `eon_engine/` (`eon-engine`): higher-level engine layer.

## Principles

- Minimalism: core primitives only.
- Extensibility: functorized modules and open polymorphic variant keys.
- Purity: systems express intent; command handlers apply effects.
- Determinism: fixed/hybrid progress modes provide stable simulation behavior.

## Build and test

Use `just`:

```sh
just tasks
just build
just run-tests
just check
just test eon_ecs/test/test_main.exe
just clean
```

## Benchmarks

```sh
just bench sparse_set
just bench entity_manager
just bench query
just bench world
just bench loop
just bench-ci
just bench-compare world
```

## Default stack (`Eon_ecs`)

For most projects, use the default aliases exposed by `Eon_ecs`:

| Role | Module |
|---|---|
| World | `Eon_ecs.World` |
| Systems | `Eon_ecs.System.Default` |
| Pipeline | `Eon_ecs.Pipeline.Default` |
| Progress | `Eon_ecs.Progress.Default` |
| Loop | `Eon_ecs.Loop.Default` |
| Buses | `Eon_ecs.Buses.Default` (instances via `signals ()`/`events ()`/`commands ()`) |

Canonical package surface:
- API contract: `eon_ecs/eon_ecs.mli`
- Composition root: `eon_ecs/eon_ecs.ml`

## Canonical usage (default modules)

```ocaml
module World    = Eon_ecs.World
module System   = Eon_ecs.System.Default
module Pipeline = Eon_ecs.Pipeline.Default
module Progress = Eon_ecs.Progress.Default
module Query    = Eon_ecs.Query
module Commands = Eon_ecs.Commands
module Loop     = Eon_ecs.Loop.Default

let world =
  let world = World.create () in
  ignore (World.register_component world ~name:"Position" ~id:0);
  ignore (World.register_component world ~name:"Velocity" ~id:1);
  let entity = World.create_entity world in
  World.add_component world entity ~name:"Position" (0.0, 0.0);
  World.add_component world entity ~name:"Velocity" (1.0, 0.0);
  world

(* Bus instances are singletons in Buses.Default — no world service registration needed. *)
let commands = Eon_ecs.Buses.Default.commands ()

let movement_system =
  System.make
    ~update:(fun world dt ->
      Query.iter2 world "Position" "Velocity"
        (fun entity (_x, _y) (vx, vy) ->
          Commands.emit commands (`Move_player (entity, (vx *. dt, vy *. dt)))))
    ~on_command:(fun world -> function
      | `Move_player (entity, (dx, dy)) ->
          begin match World.get_component world entity ~name:"Position" with
          | Some (x, y) ->
              World.set_component world entity ~name:"Position" (x +. dx, y +. dy)
          | None -> ()
          end
      | _ -> ())
    ~kind:`Fixed
    ()

let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Gameplay
  |> Pipeline.add_system `Gameplay movement_system

(* register_all calls System.register then System.attach for each system,
   wiring bus handlers automatically from Buses.Default. *)
let () = Pipeline.register_all pipeline world

let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline

let should_continue _world = true

let _final_world =
  Loop.run
    ~progress
    ~world
    ~should_continue
    ()
```

## Example: Non-reactive Snake (canonical ECS shape)

The repository includes a compact, data-centric Snake example:
- Source: `eon_ecs/examples/snake_nonreactive.ml`
- Run: `just snake_nonreactive`

Why this example is useful:
- Game logic and mutations happen in ECS systems (`input_system`, `movement_system`, `alive_system`).
- State is modeled via components/world data; systems query by component shape.
- Rendering is fully separated in `Snake_renderer`.
- Loop timing/orchestration is explicit (`Pipeline` phases with `Input -> Gameplay` ordering + `Progress.Hybrid` + `Loop.run`).

The example is intended as the reference pattern for non-reactive ECS usage.

## Loop and bus semantics

Default frame flow:
1. Collect: `Signals -> Events -> Commands`
2. `Progress.tick`
3. Drain: `Signals -> Commands -> Events`

Semantics:
- `Signals` (`Single_bus`): same-frame transient delivery.
- `Commands` (`Single_bus`): same-frame effects through handlers.
- `Events` (`Double_bus`): next-frame reactions.

When to use which bus (practical rule of thumb):
- Use `Commands` when a system already knows the intended effect (`Move`, `Set_health`, `Spawn_enemy`).
- Use `Signals` for transient notifications or fan-out (`Button_pressed`, `Collision_detected`) where multiple systems may react.
- Use `Events` for queued reactions that should become visible on the next-frame schedule.
- It is fine for systems to emit commands directly; keep world mutation in command handlers.

## Rendering in eon_ecs

Rendering is not a loop concern in `eon_ecs` — the core loop is `collect → tick → drain` and carries no renderer parameter. Rendering belongs in a pipeline system:

```ocaml
let render_system =
  System.make
    ~update:(fun world dt ->
      (* read components, draw to terminal / call backend *)
      Query.iter1 world "Position" (fun entity (x, y) ->
        ignore (entity, x, y, dt)))
    ~kind:`Variable
    ()

let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Gameplay
  |> Pipeline.add_phase `Render
  |> Pipeline.before ~earlier:`Gameplay ~later:`Render
  |> Pipeline.add_system `Render render_system
```

At the `eon_engine` layer, rendering is handled via the `Platform.S` signature which the engine loop calls after drain.

## API behavior notes

- Component names must be registered before use.
- `World.get_component`, `World.set_component`, and `World.remove_component` raise if the component name is unregistered.
- Resource store uses key identity (`Obj.repr`), avoiding overwrite on hash collisions for service/data keys.
- Pipeline phase ordering is topologically sorted and cached until phase/edge structure changes.

## Tests and benchmarks

- Unit and property tests live under `eon_ecs/test/`.
- Benchmarks live under `eon_ecs/bench/` and use Bechamel staged tests.

## Contributing

- Keep public API changes synchronized between `eon_ecs/eon_ecs.mli`, `eon_ecs/eon_ecs.ml`, and docs.
- For deterministic/order changes, add or update tests before merge.
- Use commit subjects like: `[eon :: <area>] <summary> (ecs-<id>)`.

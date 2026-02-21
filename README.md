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
| Buses | `Eon_ecs.Signals`, `Eon_ecs.Events`, `Eon_ecs.Commands` |

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

let signals  = World.get_service world `Signals  |> Option.get
let events   = World.get_service world `Events   |> Option.get
let commands = World.get_service world `Commands |> Option.get

let movement_system =
  System.make_reactive
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
  |> System.attach_handlers ~signals ~events ~commands world

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
4. Render/read-only pass

Semantics:
- `Signals` (`Single_bus`): same-frame transient delivery.
- `Commands` (`Single_bus`): same-frame effects through handlers.
- `Events` (`Double_bus`): next-frame reactions.

## Custom loop renderer example

```ocaml
module Logging_renderer = struct
  type world = Eon_ecs.World.t
  type result = unit

  let render world ~dt =
    let open Eon_ecs in
    let positions =
      let acc = ref [] in
      Query.iter1 world "Position" (fun entity (x, y) ->
        acc := (Entity_id.index entity, x, y) :: !acc);
      List.rev !acc
    in
    Logs.info (fun m -> m "[frame dt=%.3f] entities=%d" dt (List.length positions))
end

module Loop_with_logging = Eon_ecs.Loop.Make
  (Eon_ecs.Clock.Mtime)
  (Eon_ecs.Progress.Default)
  (Logging_renderer)
  (Eon_ecs.Loop_default_buses)
```

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

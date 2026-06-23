# Eon ECS Tutorial

This tutorial walks through the default `Eon_ecs` stack and shows one full frame flow:

- setup world and buses
- define and attach a reactive system
- build a pipeline
- run with hybrid progress

## 1. Setup world

```ocaml
module World    = Eon_ecs.World
module Commands = Eon_ecs.Commands

let world =
  let w = World.create () in
  ignore (World.register_component w ~name:"Position" ~id:0);
  ignore (World.register_component w ~name:"Velocity" ~id:1);
  let e = World.create_entity w in
  World.add_component w e ~name:"Position" (0.0, 0.0);
  World.add_component w e ~name:"Velocity" (4.0, 0.0);
  w
```

Important: register components first. `World.add_component` raises for unknown component names.

Bus instances live in `Eon_ecs.Buses.Default` as module-level singletons — no registration in the world needed.

## 2. Create a reactive system

```ocaml
module System = Eon_ecs.System.Default
module Query  = Eon_ecs.Query

(* Grab the singleton command bus from Buses.Default. *)
let commands = Eon_ecs.Buses.Default.commands ()

let movement =
  System.make
    ~update:(fun world dt ->
      Query.iter2 world "Position" "Velocity"
        (fun entity (_x, _y) (vx, vy) ->
          Commands.emit commands (`Move (entity, (vx *. dt, vy *. dt)))))
    ~on_command:(fun world -> function
      | `Move (entity, (dx, dy)) ->
          begin
            match World.get_component world entity ~name:"Position" with
            | Some (x, y) -> World.set_component world entity ~name:"Position" (x +. dx, y +. dy)
            | None -> ()
          end)
    ~kind:`Fixed
    ()
```

Pattern: keep update logic pure-ish by emitting commands, then mutate state in command handlers.
`Pipeline.register_all` (step 3) wires the `on_command` handler to the bus automatically — no manual `attach` call needed.

## 3. Build a pipeline

```ocaml
module Pipeline = Eon_ecs.Pipeline.Default

let pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Gameplay
  |> Pipeline.add_system `Gameplay movement

let () = Pipeline.register_all pipeline world
```

`register_all` must be called once before ticking.

## 4. Choose a progress mode

```ocaml
module Progress = Eon_ecs.Progress.Default

let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
```

Mode selection:

- `Variable` for frame-rate dependent updates
- `Fixed step` for deterministic simulation
- `Hybrid step` for fixed simulation + variable presentation logic

## 5. Run the loop

```ocaml
module Loop = Eon_ecs.Loop.Default

let should_continue _world () = true
let _final_world = Loop.run ~progress ~world ~should_continue ()
```

Default loop ordering per frame:

1. `collect` Signals -> Events -> Commands
2. `Progress.tick`
3. `drain` Signals -> Commands -> Events
4. render (no-op in `Loop.Default`)

Practical messaging guidance:

- Emit `Commands` directly when the system already knows the intended effect.
- Use `Signals` when you want transient notifications or fan-out to multiple listeners.
- Use `Events` when the reaction should follow the double-buffer next-frame delivery model.
- Keep world mutation in command handlers even if systems emit commands directly.

## 6. Add a custom renderer

Use `Eon_ecs.Loop.Make` with your own renderer module if you need frame outputs.

```ocaml
module Renderer = struct
  type world = World.t
  type result = unit
  let render world ~dt =
    Query.iter1 world "Position" (fun entity (x, y) ->
      ignore entity;
      ignore (x, y, dt))
end
```

Then wire `Loop.Make` with `Clock.Mtime`, a progress adapter, your renderer, and bus wiring.

## 7. Common pitfalls

- Forgetting to register components before adding/setting them.
- Skipping `Pipeline.register_all`.
- Emitting events and expecting same-frame behavior (`Events` are double-buffered).
- Mutating world state in side-effectful engine code instead of command handlers.

## 8. Next steps

- Add tests for your system behavior in `eon_ecs/test/`.
- Add property tests for ordering-sensitive invariants.
- Benchmark hot paths in `eon_ecs/bench/` when changing query/world internals.

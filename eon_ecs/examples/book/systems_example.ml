(* Companion example for docs/eon_ecs chapter: Systems. *)

open Eon_ecs
open Components

module System = Eon_ecs.System.Default

let make_world () =
  let world = World.create () in
  Position.register world;
  Velocity.register world;
  world

(* An `update`-only system: no bus handlers, [kind] defaults to
   `Variable if omitted — set explicitly here for clarity. *)
let movement_system () =
  System.make
    ~update:(fun world dt ->
      Query.iter2 world Position.name Velocity.name
        (fun entity (pos : Position.t) (vel : Velocity.t) ->
           let moved = { Position.x = pos.x +. (vel.dx *. dt); y = pos.y +. (vel.dy *. dt) } in
           World.set_component world entity ~name:Position.name moved))
    ~kind:`Variable
    ()

(* A handler-only system: [update] omitted, reacts to Commands instead.
   [register] runs once, before the pipeline's first tick — the natural
   place to seed any world-level setup this system depends on. *)
let spawn_system () =
  let spawned = ref 0 in
  System.make
    ~register:(fun _world -> spawned := 0)
    ~on_command:(fun world (`Spawn_at (x, y)) ->
      let e = World.create_entity world in
      World.add_component world e ~name:Position.name { Position.x = x; y };
      incr spawned)
    ()

(* A system's callbacks can be driven directly, without a Pipeline —
   useful for understanding what a Pipeline automates in the next
   chapter, and occasionally useful standalone (e.g. in a test). *)
let drive_system_directly () =
  let world  = make_world () in
  let system = movement_system () in

  let e = World.create_entity world in
  World.add_component world e ~name:Position.name { Position.x = 0.0; y = 0.0 };
  World.add_component world e ~name:Velocity.name { Velocity.dx = 2.0; dy = 0.0 };

  System.run system world 1.0;   (* one manual "tick" at dt = 1.0 *)

  match World.get_component world e ~name:Position.name with
  | Some (p : Position.t) -> assert (p.x = 2.0)
  | None -> assert false

(* Wiring a reactive system's handlers to real buses: register, then
   attach — the two steps Pipeline.register_all performs automatically
   for every system it holds. *)
let drive_reactive_system () =
  let world   = World.create () in
  Position.register world;
  let system  = spawn_system () in
  let signals = Signals.create () in
  let events  = Events.create () in
  let commands = Commands.create () in

  System.register system world;
  System.attach system world ~signals ~events ~commands;

  Commands.emit commands (`Spawn_at (3.0, 4.0));
  Commands.drain commands;   (* on_command fires here *)

  assert (World.count_entities world = 1)

let () =
  drive_system_directly ();
  drive_reactive_system ()

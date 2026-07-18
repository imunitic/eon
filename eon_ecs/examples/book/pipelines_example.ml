(* Companion example for docs/eon_ecs chapter: Pipelines. *)

open Eon_ecs
open Components

module System   = Eon_ecs.System.Default
module Pipeline = Eon_ecs.Pipeline.Default

let make_world () =
  let world = World.create () in
  Position.register world;
  Velocity.register world;
  world

let movement_system () =
  System.make
    ~update:(fun world dt ->
      Query.iter2 world Position.name Velocity.name
        (fun entity (pos : Position.t) (vel : Velocity.t) ->
           World.set_component world entity ~name:Position.name
             { Position.x = pos.x +. (vel.dx *. dt); y = pos.y +. (vel.dy *. dt) }))
    ~kind:`Variable
    ()

let input_system spawned =
  System.make
    ~on_command:(fun _world (`Log msg) -> spawned := msg :: !spawned)
    ()

(* Phases order systems relative to each other; add_system assigns a
   system to one phase. Ordering is between PHASES, not individual
   systems — every system in `Input runs (in registration order within
   the phase) before any system in `Gameplay. *)
let build_pipeline spawned =
  Pipeline.create ()
  |> Pipeline.add_phase `Input
  |> Pipeline.add_phase `Gameplay
  |> Pipeline.before ~earlier:`Input ~later:`Gameplay
  |> Pipeline.add_system `Input    (input_system spawned)
  |> Pipeline.add_system `Gameplay (movement_system ())

let run_one_tick () =
  let world    = make_world () in
  let spawned  = ref [] in
  let pipeline = build_pipeline spawned in

  let e = World.create_entity world in
  World.add_component world e ~name:Position.name { Position.x = 0.0; y = 0.0 };
  World.add_component world e ~name:Velocity.name { Velocity.dx = 1.0; dy = 0.0 };

  (* register_all wires every system's `register` and bus handlers, in
     topological phase order — the same two steps (System.register,
     System.attach) shown by hand in the Systems chapter, done once for
     every system this pipeline holds. *)
  Pipeline.register_all pipeline world;

  let world = Pipeline.run pipeline world 1.0 in
  match World.get_component world e ~name:Position.name with
  | Some (p : Position.t) -> assert (p.x = 1.0)
  | None -> assert false

(* register_all raises if called twice without an intervening reset —
   the topological order is cached on first register and the pipeline
   refuses to silently double-attach every handler. *)
let register_all_twice_raises () =
  let world    = make_world () in
  let pipeline = build_pipeline (ref []) in
  Pipeline.register_all pipeline world;
  match Pipeline.register_all pipeline world with
  | () -> assert false
  | exception Invalid_argument _ -> ()

(* reset clears bus subscribers and allows register_all to run again —
   the scene-transition pattern: tear down, rebuild, re-register. *)
let reset_for_scene_transition () =
  let world    = make_world () in
  let pipeline = build_pipeline (ref []) in
  Pipeline.register_all pipeline world;
  Pipeline.reset pipeline;
  Pipeline.register_all pipeline world   (* no longer raises *)

let () =
  run_one_tick ();
  register_all_twice_raises ();
  reset_for_scene_transition ()

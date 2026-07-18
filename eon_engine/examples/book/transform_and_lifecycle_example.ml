(* Companion example for docs/eon_engine chapter: Transform hierarchy and
   entity lifecycle. *)

open Eon_engine

let make_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

(* Both systems follow the Make(Sys : System.DISPATCH) / Default pattern.
   The explicit `before` edge is what guarantees Transform runs before
   Lifecycle — two phases with no edge between them have unspecified
   relative order, so this cannot be left implicit. *)
let make_pipeline () =
  let lifecycle  = Lifecycle_system.Default.make () in
  let transforms = Transform_system.Default.make () in
  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Transform
    |> Pipeline.Default.add_phase `Lifecycle
    |> Pipeline.Default.before ~earlier:`Transform ~later:`Lifecycle
    |> Pipeline.Default.add_system `Transform transforms
    |> Pipeline.Default.add_system `Lifecycle lifecycle
  in
  Pipeline.Default.reset pipeline;
  pipeline

let hierarchy_example () =
  let world = make_world () in
  let pipeline = make_pipeline () in

  let character = World.create_entity world in
  World.set_component world character Components.Local_transform.component
    ({ position = Math.Vec2.create 100.0 200.0; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);

  let weapon = World.create_entity world in
  World.set_component world weapon Components.Local_transform.component
    ({ position = Math.Vec2.create 20.0 0.0; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);

  (* Attach at setup time: synchronous, no command bus needed. Only valid
     BEFORE the simulation loop starts. *)
  Transform_hierarchy.attach world ~parent:character ~child:weapon;

  Pipeline.Default.register_all pipeline world;
  let world = Pipeline.Default.run pipeline world (1.0 /. 60.0) in
  Commands.drain (Buses.Default.commands ());

  (match World.get_component world weapon Components.World_transform.component with
   | Some (wt : Components.World_transform.t) ->
     assert (Float.abs (wt.position.x -. 120.0) < 1e-6);
     assert (Float.abs (wt.position.y -. 200.0) < 1e-6)
   | None -> assert false);

  (* Reparent mid-simulation goes through the command bus, not
     Transform_hierarchy.attach — Transform_system needs to see the
     mutation during drain to keep Parent/Children consistent. Detach: *)
  Single_bus.emit (Buses.Default.commands ())
    (`Reparent (Transform_hierarchy.{ entity = weapon; new_parent = None }));
  Commands.drain (Buses.Default.commands ());
  let world = Pipeline.Default.run pipeline world (1.0 /. 60.0) in
  Commands.drain (Buses.Default.commands ());
  (match World.get_component world weapon Components.Parent.component with
   | None -> ()
   | Some _ -> assert false);

  (* Destroy: Lifecycle_system handles `Destroy_entity; Transform_system
     detaches children first (registration/phase order guarantees this). *)
  Single_bus.emit (Buses.Default.commands ()) (`Destroy_entity character);
  let world = Pipeline.Default.run pipeline world (1.0 /. 60.0) in
  Commands.drain (Buses.Default.commands ());
  assert (not (World.is_alive world character));
  assert (World.is_alive world weapon)   (* was already detached above *)

let despawn_recursive_example () =
  let world = make_world () in
  let pipeline = make_pipeline () in

  let root  = World.create_entity world in
  let mid   = World.create_entity world in
  let leaf  = World.create_entity world in
  List.iter
    (fun e ->
      World.set_component world e Components.Local_transform.component
        ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
         : Components.Local_transform.t))
    [ root; mid; leaf ];
  Transform_hierarchy.attach world ~parent:root ~child:mid;
  Transform_hierarchy.attach world ~parent:mid  ~child:leaf;

  Pipeline.Default.register_all pipeline world;

  (* Called from a Parallel system's update: reads world (ro), emits
     commands — despawn_recursive itself never mutates. *)
  let emit = Single_bus.emit (Buses.Default.commands ()) in
  Transform_hierarchy.despawn_recursive (World.readonly world) root ~emit;
  Commands.drain (Buses.Default.commands ());
  let world = Pipeline.Default.run pipeline world (1.0 /. 60.0) in
  Commands.drain (Buses.Default.commands ());

  assert (not (World.is_alive world root));
  assert (not (World.is_alive world mid));
  assert (not (World.is_alive world leaf))

(* Extending Lifecycle_system: ~on_command fires BEFORE the built-in
   `Destroy_entity handler — the entity is still alive, so components are
   readable. The callback receives the FULL command type, not just
   `Destroy_entity — useful as a general lifecycle hub (spawn, teardown,
   logging all in one place). Log/Audio/Prefab.instantiate referenced in
   the original doc don't exist anywhere in the codebase; this uses a
   plain ref list instead, standing in for whatever teardown a game
   actually needs (audio stop, particle despawn, logging, ...). *)
let destroyed_log : (Eon_ecs.Entity_id.t * float * float) list ref = ref []

let extended_lifecycle_example () =
  let world = make_world () in
  let lifecycle =
    Lifecycle_system.Default.make
      ~on_command:(fun world cmd ->
        match cmd with
        | `Destroy_entity entity ->
          (match World.get_component world entity Components.Local_transform.component with
           | Some (lt : Components.Local_transform.t) ->
             destroyed_log := (entity, lt.position.x, lt.position.y) :: !destroyed_log
           | None -> ())
        | _ -> ())
      ()
  in
  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Lifecycle
    |> Pipeline.Default.add_system `Lifecycle lifecycle
  in
  Pipeline.Default.reset pipeline;

  let e = World.create_entity world in
  World.set_component world e Components.Local_transform.component
    ({ position = Math.Vec2.create 7.0 9.0; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);

  Pipeline.Default.register_all pipeline world;
  Single_bus.emit (Buses.Default.commands ()) (`Destroy_entity e);
  let world = Pipeline.Default.run pipeline world 0.0 in
  Commands.drain (Buses.Default.commands ());

  assert (not (World.is_alive world e));
  assert (!destroyed_log = [ (e, 7.0, 9.0) ])

let () =
  hierarchy_example ();
  despawn_recursive_example ();
  extended_lifecycle_example ()

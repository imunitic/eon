open Eon_engine

let create_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

let make_pipe sys =
  Pipeline.Default.create ()
  |> Pipeline.Default.add_phase `Lifecycle
  |> Pipeline.Default.add_system `Lifecycle sys

let make_pipe2 sys1 sys2 =
  Pipeline.Default.create ()
  |> Pipeline.Default.add_phase `Lifecycle
  |> Pipeline.Default.add_system `Lifecycle sys1
  |> Pipeline.Default.add_system `Lifecycle sys2

let with_pipe world pipe f =
  Pipeline.Default.register_all pipe world;
  Fun.protect ~finally:(fun () -> Pipeline.Default.reset pipe) f

let emit_cmd cmd =
  Single_bus.emit (Buses.Default.commands ()) cmd;
  Single_bus.drain (Buses.Default.commands ())

let test_destroy_entity_removes_from_world () =
  let world = create_world () in
  let sys = Lifecycle_system.Default.make () in
  let e = World.create_entity world in
  with_pipe world (make_pipe sys) (fun () ->
    Alcotest.(check bool) "alive before" true (World.is_alive world e);
    emit_cmd (`Destroy_entity e);
    Alcotest.(check bool) "dead after" false (World.is_alive world e))

let test_duplicate_destroy_is_safe () =
  let world = create_world () in
  let sys = Lifecycle_system.Default.make () in
  let e = World.create_entity world in
  with_pipe world (make_pipe sys) (fun () ->
    emit_cmd (`Destroy_entity e);
    Alcotest.(check bool) "dead after first" false (World.is_alive world e);
    emit_cmd (`Destroy_entity e);
    Alcotest.(check bool) "still dead after duplicate" false (World.is_alive world e))

let test_reparent_command_ignored () =
  let world = create_world () in
  let sys = Lifecycle_system.Default.make () in
  let e = World.create_entity world in
  with_pipe world (make_pipe sys) (fun () ->
    emit_cmd (`Reparent { Hierarchy.entity = e; new_parent = None });
    Alcotest.(check bool) "entity still alive" true (World.is_alive world e))

let test_transform_then_lifecycle_ordering () =
  let world = create_world () in
  let ts = Transform_system.Default.make () in
  let ls = Lifecycle_system.Default.make () in
  let parent = World.create_entity world in
  let child  = World.create_entity world in
  World.set_component world parent Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.; scale = Math.Vec2.one } : Components.Local_transform.t);
  World.set_component world child  Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.; scale = Math.Vec2.one } : Components.Local_transform.t);
  World.set_component world child  Components.Parent.component
    ({ entity = parent } : Components.Parent.t);
  World.set_component world parent Components.Children.component
    ({ entities = [child] } : Components.Children.t);
  (* Single_bus is FIFO: first-registered fires first.
     ts added first → fires first (detaches children). ls added second → fires last (finalizer). *)
  with_pipe world (make_pipe2 ts ls) (fun () ->
    emit_cmd (`Destroy_entity parent);
    Alcotest.(check bool) "parent destroyed"
      false (World.is_alive world parent);
    Alcotest.(check bool) "child still alive"
      true (World.is_alive world child);
    Alcotest.(check bool) "child Parent removed"
      true (World.get_component world child Components.Parent.component = None))

let tests = [
  Alcotest.test_case "Destroy_entity removes entity"     `Quick test_destroy_entity_removes_from_world;
  Alcotest.test_case "duplicate Destroy_entity is safe"  `Quick test_duplicate_destroy_is_safe;
  Alcotest.test_case "Reparent ignored by Lifecycle"     `Quick test_reparent_command_ignored;
  Alcotest.test_case "Transform then Lifecycle ordering" `Quick test_transform_then_lifecycle_ordering;
]

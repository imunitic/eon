open Eon_engine

let lt ?(rotation = 0.) ?(scale = Math.Vec2.one) position : Components.Local_transform.t =
  { position; rotation; scale }

let create_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

let make_pipe sys =
  Pipeline.Default.create ()
  |> Pipeline.Default.add_phase `Transform
  |> Pipeline.Default.add_system `Transform sys

let with_sys world sys f =
  let pipe = make_pipe sys in
  Pipeline.Default.register_all pipe world;
  Fun.protect ~finally:(fun () -> Pipeline.Default.reset pipe) f

let emit_cmd cmd =
  Single_bus.emit (Buses.Default.commands ()) cmd;
  Single_bus.drain (Buses.Default.commands ())

let wt world entity =
  World.get_component world entity Components.World_transform.component

(* ── Tests ── *)

let test_root_world_equals_local () =
  let world = create_world () in
  let sys = Transform_system.Default.make () in
  let e = World.create_entity world in
  let local = lt (Math.Vec2.{ x = 3.0; y = 4.0 }) ~rotation:1.0 in
  World.set_component world e Components.Local_transform.component local;
  with_sys world sys (fun () ->
    ignore (Pipeline.Default.run (make_pipe sys) world 0.016);
    match wt world e with
    | None -> Alcotest.fail "World_transform should be set for root entity"
    | Some (w : Components.World_transform.t) ->
      Alcotest.(check (float 0.001)) "position.x" 3.0 w.position.x;
      Alcotest.(check (float 0.001)) "position.y" 4.0 w.position.y;
      Alcotest.(check (float 0.001)) "rotation"   1.0 w.rotation)

let test_child_composition () =
  let world = create_world () in
  let sys = Transform_system.Default.make () in
  let parent = World.create_entity world in
  let child  = World.create_entity world in
  World.set_component world parent Components.Local_transform.component
    (lt (Math.Vec2.{ x = 1.0; y = 0.0 }));
  World.set_component world child Components.Local_transform.component
    (lt (Math.Vec2.{ x = 0.0; y = 1.0 }));
  World.set_component world child Components.Parent.component
    ({ entity = parent } : Components.Parent.t);
  World.set_component world parent Components.Children.component
    ({ entities = [child] } : Components.Children.t);
  with_sys world sys (fun () ->
    ignore (Pipeline.Default.run (make_pipe sys) world 0.016);
    match wt world child with
    | None -> Alcotest.fail "child should have World_transform"
    | Some (w : Components.World_transform.t) ->
      (* parent world = (1,0); child offset (0,1) with identity rotation/scale -> world = (1,1) *)
      Alcotest.(check (float 0.001)) "child world.x" 1.0 w.position.x;
      Alcotest.(check (float 0.001)) "child world.y" 1.0 w.position.y)

let test_grandchild_composition () =
  let world = create_world () in
  let sys = Transform_system.Default.make () in
  let root  = World.create_entity world in
  let mid   = World.create_entity world in
  let leaf  = World.create_entity world in
  World.set_component world root Components.Local_transform.component
    (lt (Math.Vec2.{ x = 1.0; y = 0.0 }));
  World.set_component world mid  Components.Local_transform.component
    (lt (Math.Vec2.{ x = 1.0; y = 0.0 }));
  World.set_component world leaf Components.Local_transform.component
    (lt (Math.Vec2.{ x = 1.0; y = 0.0 }));
  World.set_component world mid  Components.Parent.component
    ({ entity = root } : Components.Parent.t);
  World.set_component world leaf Components.Parent.component
    ({ entity = mid  } : Components.Parent.t);
  World.set_component world root Components.Children.component
    ({ entities = [mid]  } : Components.Children.t);
  World.set_component world mid  Components.Children.component
    ({ entities = [leaf] } : Components.Children.t);
  with_sys world sys (fun () ->
    ignore (Pipeline.Default.run (make_pipe sys) world 0.016);
    match wt world leaf with
    | None -> Alcotest.fail "leaf should have World_transform"
    | Some (w : Components.World_transform.t) ->
      Alcotest.(check (float 0.001)) "leaf world.x" 3.0 w.position.x;
      Alcotest.(check (float 0.001)) "leaf world.y" 0.0 w.position.y)

let test_reparent_attach () =
  let world = create_world () in
  let sys = Transform_system.Default.make () in
  let parent = World.create_entity world in
  let child  = World.create_entity world in
  World.set_component world parent Components.Local_transform.component (lt Math.Vec2.zero);
  World.set_component world child  Components.Local_transform.component (lt Math.Vec2.zero);
  with_sys world sys (fun () ->
    emit_cmd (`Reparent Transform_hierarchy.{ entity = child; new_parent = Some parent });
    (match World.get_component world child Components.Parent.component with
     | None -> Alcotest.fail "child should have Parent after Reparent"
     | Some (p : Components.Parent.t) ->
       Alcotest.(check bool) "Parent points to parent entity"
         true (Eon_ecs.Entity_id.equal p.entity parent));
    match World.get_component world parent Components.Children.component with
    | None -> Alcotest.fail "parent should have Children after Reparent"
    | Some (c : Components.Children.t) ->
      Alcotest.(check bool) "child in Children list"
        true (List.mem child c.entities))

let test_reparent_detach () =
  let world = create_world () in
  let sys = Transform_system.Default.make () in
  let parent = World.create_entity world in
  let child  = World.create_entity world in
  World.set_component world parent Components.Local_transform.component (lt Math.Vec2.zero);
  World.set_component world child  Components.Local_transform.component (lt Math.Vec2.zero);
  World.set_component world child  Components.Parent.component
    ({ entity = parent } : Components.Parent.t);
  World.set_component world parent Components.Children.component
    ({ entities = [child] } : Components.Children.t);
  with_sys world sys (fun () ->
    emit_cmd (`Reparent Transform_hierarchy.{ entity = child; new_parent = None });
    Alcotest.(check bool) "Parent removed after detach"
      true (World.get_component world child Components.Parent.component = None);
    Alcotest.(check bool) "Children removed when empty after detach"
      true (World.get_component world parent Components.Children.component = None))

let test_destroy_detaches_children () =
  let world = create_world () in
  let sys = Transform_system.Default.make () in
  let parent = World.create_entity world in
  let child  = World.create_entity world in
  World.set_component world parent Components.Local_transform.component (lt Math.Vec2.zero);
  World.set_component world child  Components.Local_transform.component (lt Math.Vec2.zero);
  World.set_component world child  Components.Parent.component
    ({ entity = parent } : Components.Parent.t);
  World.set_component world parent Components.Children.component
    ({ entities = [child] } : Components.Children.t);
  with_sys world sys (fun () ->
    emit_cmd (`Destroy_entity parent);
    (* Transform_system detaches but does NOT call World.destroy_entity *)
    Alcotest.(check bool) "parent still alive (Transform_system does not destroy)"
      true (World.is_alive world parent);
    Alcotest.(check bool) "child Parent removed"
      true (World.get_component world child Components.Parent.component = None);
    Alcotest.(check bool) "parent Children removed"
      true (World.get_component world parent Components.Children.component = None))

let tests = [
  Alcotest.test_case "root world = local"               `Quick test_root_world_equals_local;
  Alcotest.test_case "child composition"                `Quick test_child_composition;
  Alcotest.test_case "grandchild composition"           `Quick test_grandchild_composition;
  Alcotest.test_case "Reparent attach"                  `Quick test_reparent_attach;
  Alcotest.test_case "Reparent detach"                  `Quick test_reparent_detach;
  Alcotest.test_case "Destroy detaches children"        `Quick test_destroy_detaches_children;
]

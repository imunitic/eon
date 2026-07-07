open Eon_engine

let create_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

let collect () =
  let buf = ref [] in
  let emit (`Destroy_entity id) = buf := !buf @ [id] in
  (buf, emit)

let pos id lst =
  let rec go i = function
    | [] -> failwith "entity not found in emission list"
    | x :: _ when Eon_ecs.Entity_id.equal x id -> i
    | _ :: rest -> go (i + 1) rest
  in
  go 0 lst

(* --- despawn_recursive --- *)

let test_despawn_leaf () =
  let world = create_world () in
  let e = World.create_entity world in
  let (buf, emit) = collect () in
  Transform_hierarchy.despawn_recursive world e ~emit;
  Alcotest.(check int)  "one entity emitted" 1 (List.length !buf);
  Alcotest.(check bool) "entity is e"
    true (Eon_ecs.Entity_id.equal (List.hd !buf) e)

let test_despawn_linear_chain () =
  let world = create_world () in
  let root = World.create_entity world in
  let mid  = World.create_entity world in
  let leaf = World.create_entity world in
  World.set_component world root Components.Children.component
    ({ entities = [mid]  } : Components.Children.t);
  World.set_component world mid  Components.Children.component
    ({ entities = [leaf] } : Components.Children.t);
  let (buf, emit) = collect () in
  Transform_hierarchy.despawn_recursive world root ~emit;
  Alcotest.(check int)  "all 3 emitted"   3 (List.length !buf);
  Alcotest.(check bool) "leaf before mid" true (pos leaf !buf < pos mid  !buf);
  Alcotest.(check bool) "mid before root" true (pos mid  !buf < pos root !buf)

let test_despawn_branching () =
  let world = create_world () in
  let root = World.create_entity world in
  let c1   = World.create_entity world in
  let c2   = World.create_entity world in
  let leaf = World.create_entity world in
  World.set_component world root Components.Children.component
    ({ entities = [c1; c2] } : Components.Children.t);
  World.set_component world c1 Components.Children.component
    ({ entities = [leaf] }   : Components.Children.t);
  let (buf, emit) = collect () in
  Transform_hierarchy.despawn_recursive world root ~emit;
  Alcotest.(check int)  "all 4 emitted"  4 (List.length !buf);
  Alcotest.(check bool) "leaf before c1" true (pos leaf !buf < pos c1   !buf);
  Alcotest.(check bool) "c1 before root" true (pos c1   !buf < pos root !buf);
  Alcotest.(check bool) "c2 before root" true (pos c2   !buf < pos root !buf);
  Alcotest.(check bool) "root is last"   true (pos root !buf = 3)

(* --- Transform_hierarchy.attach --- *)

let test_attach_single_child () =
  let world = create_world () in
  let parent = World.create_entity world in
  let child  = World.create_entity world in
  Transform_hierarchy.attach world ~parent ~child;
  (match World.get_component world child Components.Parent.component with
   | None -> Alcotest.fail "child should have Parent component"
   | Some (p : Components.Parent.t) ->
     Alcotest.(check bool) "Parent.entity = parent"
       true (Eon_ecs.Entity_id.equal p.entity parent));
  match World.get_component world parent Components.Children.component with
  | None -> Alcotest.fail "parent should have Children component"
  | Some (c : Components.Children.t) ->
    Alcotest.(check bool) "child in Children list"
      true (List.exists (Eon_ecs.Entity_id.equal child) c.entities)

let test_attach_multiple_children () =
  let world = create_world () in
  let parent = World.create_entity world in
  let c1 = World.create_entity world in
  let c2 = World.create_entity world in
  Transform_hierarchy.attach world ~parent ~child:c1;
  Transform_hierarchy.attach world ~parent ~child:c2;
  match World.get_component world parent Components.Children.component with
  | None -> Alcotest.fail "parent should have Children"
  | Some (c : Components.Children.t) ->
    Alcotest.(check int)  "two children"    2 (List.length c.entities);
    Alcotest.(check bool) "c1 in Children"
      true (List.exists (Eon_ecs.Entity_id.equal c1) c.entities);
    Alcotest.(check bool) "c2 in Children"
      true (List.exists (Eon_ecs.Entity_id.equal c2) c.entities)

let tests = [
  Alcotest.test_case "despawn_recursive leaf"      `Quick test_despawn_leaf;
  Alcotest.test_case "despawn_recursive linear"    `Quick test_despawn_linear_chain;
  Alcotest.test_case "despawn_recursive branching" `Quick test_despawn_branching;
  Alcotest.test_case "attach single child"         `Quick test_attach_single_child;
  Alcotest.test_case "attach multiple children"    `Quick test_attach_multiple_children;
]

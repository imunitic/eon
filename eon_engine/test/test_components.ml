open Eon_engine

(* [Components.Foo] is constrained to [Component.S] ([type t], [component],
   [name] only — see components.mli) so field labels aren't in scope through
   that path, the same transparency gap ecs-044 found for application code.
   Reach the raw internal modules directly for the shape tests below,
   matching the pattern other eon_engine tests already use (e.g.
   test_prop_prefab.ml's [Eon_engine__Edn_document]). *)
module Raw_local_transform = Eon_engine__Local_transform
module Raw_world_transform = Eon_engine__World_transform
module Raw_parent = Eon_engine__Parent
module Raw_children = Eon_engine__Children
module Raw_velocity = Eon_engine__Velocity
module Raw_sprite = Eon_engine__Sprite
module Raw_animation = Eon_engine__Animation
module Raw_camera = Eon_engine__Camera
module Raw_collider = Eon_engine__Collider
module Raw_tag = Eon_engine__Tag

(* ============================================================================ *)
(* Test Components                                                              *)
(* ============================================================================ *)

(* ============================================================================ *)
(* Tests                                                                        *)
(* ============================================================================ *)

let test_component_creation () =
  let comp = Components.Local_transform.component in
  Alcotest.(check string) "Component name should match" "Local_transform" (Components.name comp)


let test_register_automatic_id () =
  let world = World.create () in
  let comp1 = Components.Local_transform.component in
  let comp2 = Components.Velocity.component in
  
  let result1 = World.register world comp1 in
  let result2 = World.register world comp2 in
  
  (match result1, result2 with
   | Components.Registered, Components.Registered -> ()
   | _ -> Alcotest.fail "Automatic registration should succeed");
  
  (* Try to register same component again *)
  let result3 = World.register world comp1 in
  (match result3 with
   | Components.Already_registered -> ()
   | _ -> Alcotest.fail "Re-registration should be idempotent")


let test_is_registered () =
  let world = World.create () in
  let comp = Components.Velocity.component in
  
  Alcotest.(check bool) "Component should not be registered initially" false
    (World.is_registered world comp);
  
  let _ = World.register world comp in
  Alcotest.(check bool) "Component should be registered after registration" true
    (World.is_registered world comp)


let test_same_name_idempotency () =
  let world = World.create () in
  
  (* Create two distinct descriptor objects with the same name *)
  let comp1 : unit Components.t = Components.component "SameNameTest" in
  let comp2 : unit Components.t = Components.component "SameNameTest" in
  
  let result1 = World.register world comp1 in
  (match result1 with
   | Components.Registered -> ()
   | _ -> Alcotest.fail "First registration should succeed");
  
  (* Same name but different object should be idempotent *)
  let result2 = World.register world comp2 in
  (match result2 with
   | Components.Already_registered -> ()
   | _ -> Alcotest.fail "Same name should be idempotent")


let test_engine_components () =
  let world = World.create () in
  Components.Engine_components.register_all world;

  Alcotest.(check bool) "Local_transform should be registered" true
    (World.is_registered world Components.Local_transform.component);
  Alcotest.(check bool) "World_transform should be registered" true
    (World.is_registered world Components.World_transform.component);
  Alcotest.(check bool) "Parent should be registered" true
    (World.is_registered world Components.Parent.component);
  Alcotest.(check bool) "Children should be registered" true
    (World.is_registered world Components.Children.component);
  Alcotest.(check bool) "Velocity component should be registered" true
    (World.is_registered world Components.Velocity.component);
  Alcotest.(check bool) "Camera component should be registered" true
    (World.is_registered world Components.Camera.component);
  Alcotest.(check bool) "Collider component should be registered" true
    (World.is_registered world Components.Collider.component);
  Alcotest.(check bool) "Tag component should be registered" true
    (World.is_registered world Components.Tag.component);
  Alcotest.(check bool) "Animation component should be registered" true
    (World.is_registered world Components.Animation.component);
  Alcotest.(check bool) "Sprite component should be registered" true
    (World.is_registered world Components.Sprite.component)


let test_module_based_components () =
  (* Example of module-based component definition - this is the recommended pattern *)
  let module CustomPosition = struct
    type t = float * float
    let component : t Components.t = Components.component "CustomPosition"
  end in
  
  let module CustomVelocity = struct
    type t = float * float  
    let component : t Components.t = Components.component "CustomVelocity"
  end in
  
  let world = World.create () in
  let result1 = World.register world CustomPosition.component in
  let result2 = World.register world CustomVelocity.component in
  
  (match result1, result2 with
   | Components.Registered, Components.Registered -> ()
   | _ -> Alcotest.fail "Module-based components should register successfully");
  
  Alcotest.(check bool) "CustomPosition should be registered" true
    (World.is_registered world CustomPosition.component);
  
  Alcotest.(check bool) "CustomVelocity should be registered" true
    (World.is_registered world CustomVelocity.component)


let test_cross_world_isolation () =
  (* Create two separate worlds *)
  let world_a = World.create () in
  let world_b = World.create () in
  let comp = Components.Collider.component in
  
  (* Register in world_a only *)
  let result = World.register world_a comp in
  (match result with
   | Components.Registered -> ()
   | _ -> Alcotest.fail "Registration in world_a should succeed");
  
  (* Verify component is registered in world_a *)
  Alcotest.(check bool) "Component should be registered in world_a" true
    (World.is_registered world_a comp);
  
  (* Verify component is NOT registered in world_b *)
  Alcotest.(check bool) "Component should NOT be registered in world_b" false
    (World.is_registered world_b comp);
  
  (* Try to register same component in world_b - should succeed *)
  let result_b = World.register world_b comp in
  (match result_b with
   | Components.Registered -> ()
   | _ -> Alcotest.fail "Registration in world_b should succeed as separate world");
  
  (* Now both worlds should have the component registered *)
  Alcotest.(check bool) "Component should now be registered in world_b" true
    (World.is_registered world_b comp)


let test_name_round_trip () =
  (* Test that the name round-trips correctly through Components.name *)
  Alcotest.(check string)
    "Local_transform component name"
    "Local_transform" (Components.name Components.Local_transform.component);

  Alcotest.(check string)
    "Velocity component name"
    "Velocity" (Components.name Components.Velocity.component);

  Alcotest.(check string)
    "Collider component name"
    "Collider" (Components.name Components.Collider.component)


(* ============================================================================ *)
(* Minimal shape/type tests — one per component descriptor                      *)
(*                                                                              *)
(* test_engine_components above only proves each component *registers*.        *)
(* These confirm each component's own field values / variants actually         *)
(* round-trip through its [t] — deliberately minimal, a handful of              *)
(* assertions each, not a battery.                                             *)
(* ============================================================================ *)

let test_local_transform_shape () =
  let t : Raw_local_transform.t =
    { position = { Math.Vec2.x = 1.0; y = 2.0 }; rotation = 0.5; scale = { x = 3.0; y = 4.0 } }
  in
  Alcotest.(check (float 0.0)) "position.x" 1.0 t.position.x;
  Alcotest.(check (float 0.0)) "position.y" 2.0 t.position.y;
  Alcotest.(check (float 0.0)) "rotation" 0.5 t.rotation;
  Alcotest.(check (float 0.0)) "scale.x" 3.0 t.scale.x

let test_world_transform_shape () =
  let t : Raw_world_transform.t =
    { position = { Math.Vec2.x = 5.0; y = 6.0 }; rotation = 1.0; scale = { x = 1.0; y = 1.0 } }
  in
  Alcotest.(check (float 0.0)) "position.x" 5.0 t.position.x;
  Alcotest.(check (float 0.0)) "rotation" 1.0 t.rotation

let test_parent_shape () =
  let e = Eon_ecs.Entity_id.make 3 0 in
  let t : Raw_parent.t = { entity = e } in
  Alcotest.(check bool) "entity round-trips" true (Eon_ecs.Entity_id.equal e t.entity)

let test_children_shape () =
  let e0 = Eon_ecs.Entity_id.make 0 0 in
  let e1 = Eon_ecs.Entity_id.make 1 0 in
  let t : Raw_children.t = { entities = [ e0; e1 ] } in
  Alcotest.(check int) "two children" 2 (List.length t.entities)

let test_velocity_shape () =
  let t : Raw_velocity.t = { dx = 1.5; dy = -2.5 } in
  Alcotest.(check (float 0.0)) "dx" 1.5 t.dx;
  Alcotest.(check (float 0.0)) "dy" (-2.5) t.dy

let test_sprite_shape () =
  let t : Raw_sprite.t = { texture_id = "hero.png"; layer = 2; flip_x = true; flip_y = false } in
  Alcotest.(check string) "texture_id" "hero.png" t.texture_id;
  Alcotest.(check int) "layer" 2 t.layer;
  Alcotest.(check bool) "flip_x" true t.flip_x;
  Alcotest.(check bool) "flip_y" false t.flip_y

let test_animation_shape () =
  let t : Raw_animation.t = { clip = "walk"; frame = 3; speed = 1.5; playing = true } in
  Alcotest.(check string) "clip" "walk" t.clip;
  Alcotest.(check int) "frame" 3 t.frame;
  Alcotest.(check (float 0.0)) "speed" 1.5 t.speed;
  Alcotest.(check bool) "playing" true t.playing

let test_camera_shape () =
  let t : Raw_camera.t = { zoom = Some 2.0; rotation = None; viewport = Some (0.0, 0.0, 800.0, 600.0) } in
  Alcotest.(check (option (float 0.0))) "zoom" (Some 2.0) t.zoom;
  Alcotest.(check (option (float 0.0))) "rotation" None t.rotation;
  (match t.viewport with
   | Some (x, y, w, h) ->
       Alcotest.(check (float 0.0)) "viewport x" 0.0 x;
       Alcotest.(check (float 0.0)) "viewport w" 800.0 w;
       ignore y; ignore h
   | None -> Alcotest.fail "expected a viewport")

let test_collider_shape () =
  let circle : Raw_collider.t =
    { shape = Circle 5.0; layer = 1; mask = 0xFF; is_trigger = false; is_static = true }
  in
  let box : Raw_collider.t =
    { shape = Box (2.0, 3.0); layer = 0; mask = 0; is_trigger = true; is_static = false }
  in
  let capsule : Raw_collider.t =
    { shape = Capsule (1.0, 4.0); layer = 0; mask = 0; is_trigger = false; is_static = false }
  in
  (match circle.shape with
   | Circle r -> Alcotest.(check (float 0.0)) "circle radius" 5.0 r
   | _ -> Alcotest.fail "expected Circle");
  (match box.shape with
   | Box (w, h) ->
       Alcotest.(check (float 0.0)) "box width" 2.0 w;
       Alcotest.(check (float 0.0)) "box height" 3.0 h
   | _ -> Alcotest.fail "expected Box");
  (match capsule.shape with
   | Capsule (r, h) ->
       Alcotest.(check (float 0.0)) "capsule radius" 1.0 r;
       Alcotest.(check (float 0.0)) "capsule height" 4.0 h
   | _ -> Alcotest.fail "expected Capsule");
  Alcotest.(check bool) "is_static" true circle.is_static;
  Alcotest.(check bool) "is_trigger" true box.is_trigger

let test_tag_shape () =
  let t : Raw_tag.t = { value = "enemy" } in
  Alcotest.(check string) "value" "enemy" t.value

(* ============================================================================ *)
(* Test Suite Registration                                                      *)
(* ============================================================================ *)

let tests = [
  "component creation", `Quick, test_component_creation;
  "register automatic id", `Quick, test_register_automatic_id;
  "is_registered", `Quick, test_is_registered;
  "same name idempotency", `Quick, test_same_name_idempotency;
  "engine components", `Quick, test_engine_components;
  "module-based components", `Quick, test_module_based_components;
  "cross-world isolation", `Quick, test_cross_world_isolation;
  "name round-trip", `Quick, test_name_round_trip;
  "Local_transform shape", `Quick, test_local_transform_shape;
  "World_transform shape", `Quick, test_world_transform_shape;
  "Parent shape", `Quick, test_parent_shape;
  "Children shape", `Quick, test_children_shape;
  "Velocity shape", `Quick, test_velocity_shape;
  "Sprite shape", `Quick, test_sprite_shape;
  "Animation shape", `Quick, test_animation_shape;
  "Camera shape", `Quick, test_camera_shape;
  "Collider shape", `Quick, test_collider_shape;
  "Tag shape", `Quick, test_tag_shape;
]

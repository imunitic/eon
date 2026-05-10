open Eon_engine

(* Test basic component creation and registration *)
let test_component_creation () =
  let comp : int Components.t = Components.component "TestComponent" in
  Alcotest.(check string) "Component name should match" "TestComponent" (Components.name comp)

let test_register_automatic_id () =
  let world = World.create () in
  let comp1 = Components.component "AutoComponent1" in
  let comp2 = Components.component "AutoComponent2" in
  
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
  let comp = Components.component "Velocity" in
  
  Alcotest.(check bool) "Component should not be registered initially" false
    (World.is_registered world comp);
  
  let _ = World.register world comp in
  Alcotest.(check bool) "Component should be registered after registration" true
    (World.is_registered world comp)

let test_same_name_idempotency () =
  let world = World.create () in
  let comp1 = Components.component "Health" in
  let comp2 = Components.component "Health" in  (* Same name *)
  
  let result1 = World.register world comp1 in
  (match result1 with
   | Components.Registered -> ()
   | _ -> Alcotest.fail "First registration should succeed");
  
  (* Same name should be idempotent *)
  let result2 = World.register world comp2 in
  (match result2 with
   | Components.Already_registered -> ()
   | _ -> Alcotest.fail "Same name should be idempotent")

let test_engine_components () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  
  (* Verify registration by checking that components with engine names exist *)
  Alcotest.(check bool) "Position component should be registered" true
    (World.is_registered world Components.Position.component);
  Alcotest.(check bool) "Velocity component should be registered" true
    (World.is_registered world Components.Velocity.component);
  Alcotest.(check bool) "Rotation component should be registered" true
    (World.is_registered world Components.Rotation.component);
  Alcotest.(check bool) "Scale component should be registered" true
    (World.is_registered world Components.Scale.component);
  Alcotest.(check bool) "Camera component should be registered" true
    (World.is_registered world Components.Camera.component);
  Alcotest.(check bool) "Collider component should be registered" true
    (World.is_registered world Components.Collider.component);
  Alcotest.(check bool) "Tag component should be registered" true
    (World.is_registered world Components.Tag.component)

let test_module_based_components () =
  (* Example of module-based component definition *)
  let module Position = struct
    type t = float * float
    let component : t Components.t = Components.component "Position"
  end in
  
  let module Velocity = struct
    type t = float * float  
    let component : t Components.t = Components.component "Velocity"
  end in
  
  let world = World.create () in
  let result1 = World.register world Position.component in
  let result2 = World.register world Velocity.component in
  
  (match result1, result2 with
   | Components.Registered, Components.Registered -> ()
   | _ -> Alcotest.fail "Module-based components should register successfully");
  
  Alcotest.(check bool) "Position should be registered" true
    (World.is_registered world Position.component);
  
  Alcotest.(check bool) "Velocity should be registered" true
    (World.is_registered world Velocity.component)

let test_cross_world_isolation () =
  (* Create two separate worlds *)
  let world_a = World.create () in
  let world_b = World.create () in
  let comp = Components.component "IsolatedComponent" in
  
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
  let test_names = ["Simple"; "With Spaces"; "CamelCase"; "snake_case"; "kebab-case"; "123Numbers"] in
  
  List.iter (fun expected_name ->
    let comp = Components.component expected_name in
    let actual_name = Components.name comp in
    Alcotest.(check string) 
      (Printf.sprintf "name round-trip for '%s'" expected_name)
      expected_name actual_name
  ) test_names

let tests = [
  "component creation", `Quick, test_component_creation;
  "register automatic id", `Quick, test_register_automatic_id;
  "is_registered", `Quick, test_is_registered;
  "same name idempotency", `Quick, test_same_name_idempotency;
  "engine components", `Quick, test_engine_components;
  "module-based components", `Quick, test_module_based_components;
  "cross-world isolation", `Quick, test_cross_world_isolation;
  "name round-trip", `Quick, test_name_round_trip;
]

(** Tests for Eon_engine.World data and service plane. *)

open Eon_engine

let test_add_get_data () =
  let world = World.create () in
  let key = `TestKey in
  let value = 42 in
  World.add_data world key value;
  match World.get_data world key with
  | Some v -> Alcotest.(check int) "data matches" value v
  | None -> Alcotest.fail "Data not found"

let test_set_data () =
  let world = World.create () in
  let key = `TestKey in
  World.add_data world key 42;
  World.set_data world key 100;
  match World.get_data world key with
  | Some v -> Alcotest.(check int) "data replaced" 100 v
  | None -> Alcotest.fail "Data not found"

let test_add_data_twice () =
  let world = World.create () in
  let key = `TestKey in
  World.add_data world key 42;
  World.add_data world key 100;
  match World.get_data world key with
  | Some v -> Alcotest.(check int) "second add overwrites first" 100 v
  | None -> Alcotest.fail "Data not found"

let test_count_data () =
  let world = World.create () in
  Alcotest.(check int) "initial count" 0 (World.count_data world);
  World.add_data world `Key1 1;
  Alcotest.(check int) "count after add" 1 (World.count_data world);
  World.add_data world `Key2 2;
  Alcotest.(check int) "count after second add" 2 (World.count_data world);
  World.set_data world `Key1 10;
  Alcotest.(check int) "count after set (no change)" 2 (World.count_data world)

let test_add_get_service () =
  let world = World.create () in
  let key = `TestService in
  let service = "my service" in
  World.add_service world key service;
  match World.get_service world key with
  | Some s -> Alcotest.(check string) "service matches" service s
  | None -> Alcotest.fail "Service not found"

let test_add_service_twice () =
  let world = World.create () in
  let key = `TestService in
  World.add_service world key "first";
  World.add_service world key "second";
  match World.get_service world key with
  | Some s -> Alcotest.(check string) "second add overwrites first" "second" s
  | None -> Alcotest.fail "Service not found"

let test_service_not_found () =
  let world = World.create () in
  match World.get_service world `UnknownService with
  | None -> ()
  | Some _ -> Alcotest.fail "Service should not be found"

let test_data_not_found () =
  let world = World.create () in
  match World.get_data world `UnknownKey with
  | None -> ()
  | Some _ -> Alcotest.fail "Data should not be found"

let test_list_services () =
  let world = World.create () in
  Alcotest.(check (list int)) "initial list" [] (World.list_services world);
  World.add_service world `Service1 "service1";
  World.add_service world `Service2 "service2";
  let services = World.list_services world in
  Alcotest.(check int) "two services registered" 2 (List.length services)

module Pos = struct
  type t = { x : float; y : float }
  let component : t Components.t = Components.component "Pos"
end

module Vel = struct
  type t = { dx : float; dy : float }
  let component : t Components.t = Components.component "Vel"
end

let test_iter_entities_basic () =
  let world = World.create () in
  ignore (World.register world Pos.component);
  ignore (World.register world Vel.component);
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 Pos.component { Pos.x = 1.0; y = 2.0 };
  World.add_component world e1 Vel.component { Vel.dx = 0.5; dy = 0.5 };
  World.add_component world e2 Pos.component { Pos.x = 3.0; y = 4.0 };
  (* e2 has no Vel *)
  let count = ref 0 in
  World.iter_entities world ["Pos"; "Vel"] (fun _ -> incr count);
  Alcotest.(check int) "intersection visits only e1" 1 !count

let test_iter_entities_unregistered_is_false () =
  let world = World.create () in
  Alcotest.check_raises
    "unregistered name raises"
    (Invalid_argument "iter_entities: unregistered component: Ghost")
    (fun () -> World.iter_entities world ["Ghost"] (fun _ -> ()))

let test_has_component_basic () =
  let world = World.create () in
  ignore (World.register world Pos.component);
  let e = World.create_entity world in
  Alcotest.(check bool) "absent before add" false
    (World.has_component world e "Pos");
  World.add_component world e Pos.component { Pos.x = 0.0; y = 0.0 };
  Alcotest.(check bool) "present after add" true
    (World.has_component world e "Pos")

let test_has_component_unregistered_returns_false () =
  let world = World.create () in
  let e = World.create_entity world in
  Alcotest.(check bool) "unregistered name returns false (no exception)" false
    (World.has_component world e "NoSuchComponent")

let test_per_world_id_counter_isolation () =
  let w1 = World.create () in
  let w2 = World.create () in
  ignore (World.register w1 Pos.component);
  ignore (World.register w2 Pos.component);
  let e1 = World.create_entity w1 in
  let e2 = World.create_entity w2 in
  World.add_component w1 e1 Pos.component { Pos.x = 1.0; y = 0.0 };
  World.add_component w2 e2 Pos.component { Pos.x = 2.0; y = 0.0 };
  (match World.get_component w1 e1 Pos.component with
   | Some p -> Alcotest.(check (float 0.001)) "w1 entity x=1" 1.0 p.Pos.x
   | None -> Alcotest.fail "w1 entity missing component");
  (match World.get_component w2 e2 Pos.component with
   | Some p -> Alcotest.(check (float 0.001)) "w2 entity x=2" 2.0 p.Pos.x
   | None -> Alcotest.fail "w2 entity missing component")

let test_per_world_id_counter_dense () =
  (* Two components registered in one world get consecutive IDs 0 and 1.
     The only observable effect is that both can be used without collision. *)
  let world = World.create () in
  let r1 = World.register world Pos.component in
  let r2 = World.register world Vel.component in
  Alcotest.(check bool) "first registration is Registered"
    true (r1 = Components.Registered);
  Alcotest.(check bool) "second registration is Registered"
    true (r2 = Components.Registered);
  (* Re-registering should yield Already_registered, not Registered. *)
  let r3 = World.register world Pos.component in
  Alcotest.(check bool) "re-registration is Already_registered"
    true (r3 = Components.Already_registered)

let tests =
  [
    ("add_data/get_data", `Quick, test_add_get_data);
    ("set_data", `Quick, test_set_data);
    ("add_data_twice", `Quick, test_add_data_twice);
    ("count_data", `Quick, test_count_data);
    ("add_service/get_service", `Quick, test_add_get_service);
    ("add_service_twice", `Quick, test_add_service_twice);
    ("service_not_found", `Quick, test_service_not_found);
    ("data_not_found", `Quick, test_data_not_found);
    ("list_services", `Quick, test_list_services);
    ("iter_entities basic", `Quick, test_iter_entities_basic);
    ("iter_entities unregistered raises", `Quick, test_iter_entities_unregistered_is_false);
    ("has_component basic", `Quick, test_has_component_basic);
    ("has_component unregistered returns false", `Quick, test_has_component_unregistered_returns_false);
    ("per-world id counter isolation", `Quick, test_per_world_id_counter_isolation);
    ("per-world id counter dense", `Quick, test_per_world_id_counter_dense);
  ]

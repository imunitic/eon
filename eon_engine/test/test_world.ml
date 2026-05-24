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
  ]

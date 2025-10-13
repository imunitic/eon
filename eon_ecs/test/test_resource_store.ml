open Alcotest

module Resource_store = Eon_ecs__Resource_store

(* 1. Create and empty store *)
let test_create_empty () =
  let store = Resource_store.create () in
  check int "initial services size" 0 (List.length (Resource_store.list_services store));
  check int "inital data size" 0 (Resource_store.count_data store)

(* data-plane tests *)
(* 2. Add and get value fro the data-plane *)
let test_data_add_get () =
  let store = Resource_store.create () in
  Resource_store.add_data store 0 (42 : int);
  match Resource_store.get_data store 0 with
  | Some v -> check int "value retrieved" 42 v
  | None -> fail "value not found"

(* 3. Get non-existent key *)
let test_data_missing_key () =
  let store = Resource_store.create () in
  match Resource_store.get_data store 0  with
  | None -> ()  (* OK *)
  | Some _ -> fail "expected None for missing key"

(* 4. Remove key *)
let test_data_remove_key () =
  let store = Resource_store.create () in
  Resource_store.add_data store 0  (99 : int);
  Resource_store.remove_data store 0;
  match Resource_store.get_data store 0 with
  | None -> ()
  | Some _ -> fail "key was not removed"

(* service-plane tests *)
(* 5. Add and get value from the service-plane *)
let test_service_add_get () =
  let store = Resource_store.create () in
  Resource_store.add_service store (Resource_store.of_typename "health") true;
  match Resource_store.get_service store (Resource_store.of_typename "health") with
  | Some v -> check bool "value retrieved" true v
  | None -> fail "value not found"

(* 6. Get non-existent key *)
let test_service_missing_key () =
  let store = Resource_store.create () in
  match Resource_store.get_service store (Resource_store.of_typename "health") with
  | None -> ()
  | Some _ -> fail "expected None for missing key"

let test_service_remove_key () =
  let store = Resource_store.create () in
  Resource_store.add_service store (Resource_store.of_typename "health") true;
  Resource_store.remove_service store (Resource_store.of_typename "health");
  match Resource_store.get_service store (Resource_store.of_typename "health") with
  | None -> ()
  | Some _ -> fail "key was not removed"

let tests = [
  test_case "create empty" `Quick test_create_empty;
  test_case "data-plane :: add/get" `Quick test_data_add_get;
  test_case "data-plane :: missing key" `Quick test_data_missing_key;
  test_case "data-plane :: remove key" `Quick test_data_remove_key;
  test_case "service-plane :: add/get" `Quick test_service_add_get;
  test_case "service-plane :: missing key" `Quick test_service_missing_key;
  test_case "service-plane :: remove key" `Quick test_service_remove_key;

]

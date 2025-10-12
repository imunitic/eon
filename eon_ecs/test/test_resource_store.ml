open Alcotest

module Resource_store = Eon_ecs__Resource_store

(* 1. Create and empty store *)
let test_create_empty () =
  let store = Resource_store.create () in
  check int "initial size" 0 (List.length (Resource_store.list_keys store))

(* 2. Add and get value *)
let test_add_get () =
  let store = Resource_store.create () in
  Resource_store.add store (Resource_store.of_typename "position") (42 : int);
  match Resource_store.get store (Resource_store.of_typename "position") with
  | Some v -> check int "value retrieved" 42 v
  | None -> fail "value not found"

(* 3. Get non-existent key *)
let test_missing_key () =
  let store = Resource_store.create () in
  match Resource_store.get store (Resource_store.of_typename "ghost") with
  | None -> ()  (* OK *)
  | Some _ -> fail "expected None for missing key"

(* 4. Remove key *)
let test_remove_key () =
  let store = Resource_store.create () in
  Resource_store.add store (Resource_store.of_typename "health") (99 : int);
  Resource_store.remove store (Resource_store.of_typename "health");
  match Resource_store.get store (Resource_store.of_typename "health") with
  | None -> ()
  | Some _ -> fail "key was not removed"

(* 5. Clear store *)
let test_clear_store () =
  let store = Resource_store.create () in
  Resource_store.add store (Resource_store.of_typename "a") true;
  Resource_store.add store (Resource_store.of_typename "b") false;
  Resource_store.clear store;
  check int "cleared size" 0 (List.length (Resource_store.list_keys store))

(* 6. List keys *)
let test_list_keys () =
  let store = Resource_store.create () in
  Resource_store.add store (Resource_store.of_typename "foo") 1;
  Resource_store.add store (Resource_store.of_typename "bar") 2;
  let keys = Resource_store.list_keys store in
  check bool "contains foo" true (List.mem (Resource_store.of_typename "foo") keys);
  check bool "contains bar" true (List.mem (Resource_store.of_typename "bar") keys)

let tests = [
  test_case "create empty" `Quick test_create_empty;
  test_case "add/get" `Quick test_add_get;
  test_case "missing key" `Quick test_missing_key;
  test_case "remove key" `Quick test_remove_key;
  test_case "clear store" `Quick test_clear_store;
  test_case "list keys" `Quick test_list_keys;
]

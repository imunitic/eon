open Alcotest

module Component_registry = Eon_ecs__Component_registry
module Component = Eon_ecs__Component

let test_create_empty () =
  let reg = Component_registry.create () in
  check int "initial count" 0 (Component_registry.count reg)

let test_register_and_find () =
  let reg = Component_registry.create () in
  let comp = Component_registry.register reg ~name:"position" ~id:1 in
  match Component_registry.find reg ~name:"position" with
  | Some found ->
      check bool "same component" true (found.id = comp.id)
  | None -> fail "component not found"

let test_duplicate_register () =
  let reg = Component_registry.create () in
  ignore (Component_registry.register reg ~name:"health" ~id:2);
  check_raises "duplicate registration" (Failure "Component already registered: health")
    (fun () -> ignore (Component_registry.register reg ~name:"health" ~id:3))

let test_find_missing () =
  let reg = Component_registry.create () in
  match Component_registry.find reg ~name:"not_there" with
  | None -> ()
  | Some _ -> fail "unexpected component found"

let test_iter () =
  let reg = Component_registry.create () in
  ignore (Component_registry.register reg ~name:"xform" ~id:0);
  ignore (Component_registry.register reg ~name:"velocity" ~id:1);
  let names = ref [] in
  Component_registry.iter (fun (Component.Component c) -> names := c.Component.name :: !names) reg;
  check bool "iterated all" true (List.length !names = 2)

let test_count () =
  let reg = Component_registry.create () in
  ignore (Component_registry.register reg ~name:"pos" ~id:0);
  ignore (Component_registry.register reg ~name:"vel" ~id:1);
  check int "count = 2" 2 (Component_registry.count reg)

let tests = [
  test_case "create empty" `Quick test_create_empty;
  test_case "register and find" `Quick test_register_and_find;
  test_case "duplicate register" `Quick test_duplicate_register;
  test_case "find missing" `Quick test_find_missing;
  test_case "iterate" `Quick test_iter;
  test_case "count" `Quick test_count;
]

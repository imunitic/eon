open Eon_ecs

module Entity_manager = Eon_ecs__Entity_manager
module Component = Eon_ecs__Component
module Component_registry = Eon_ecs__Component_registry
module Sparse_set = Eon_ecs__Sparse_set

let test_create_and_destroy () =
  let mgr = Entity_manager.create 4 in
  let e1 = Entity_manager.create_entity mgr in
  let e2 = Entity_manager.create_entity mgr in
  Alcotest.(check bool) "entities alive" true
    (Entity_manager.is_alive mgr e1 && Entity_manager.is_alive mgr e2);
  Entity_manager.destroy_entity mgr e1;
  Alcotest.(check bool) "e1 dead" false (Entity_manager.is_alive mgr e1);
  Alcotest.(check bool) "e2 still alive" true (Entity_manager.is_alive mgr e2)

let test_reuse_id () =
  let mgr = Entity_manager.create 1 in
  let e1 = Entity_manager.create_entity mgr in
  Entity_manager.destroy_entity mgr e1;
  let e2 = Entity_manager.create_entity mgr in
  Alcotest.(check int) "index reused" (Entity_id.index e1) (Entity_id.index e2);
  Alcotest.(check bool) "different generation"
    true ((Entity_id.generation e1) <> (Entity_id.generation e2))

let test_capacity_growth () =
  let mgr = Entity_manager.create 2 in
  ignore (Entity_manager.create_entity mgr);
  ignore (Entity_manager.create_entity mgr);
  ignore (Entity_manager.create_entity mgr); (* triggers grow *)
  Alcotest.(check int) "capacity doubled" 4 (Entity_manager.capacity mgr)

let test_deterministic_allocation () =
  let mgr = Entity_manager.create 4 in
  let ids = List.init 4 (fun _ -> Entity_manager.create_entity mgr) in
  Alcotest.(check (list int)) "indices are sequential"
    [0; 1; 2; 3]
    (List.map (fun id -> Entity_id.index id) ids)

let test_invalid_destroy () =
  let mgr = Entity_manager.create 2 in
  let e = Entity_manager.create_entity mgr in
  Entity_manager.destroy_entity mgr e;
  Alcotest.(check bool) "entity dead" false (Entity_manager.is_alive mgr e);
  (* destroy again — should not crash or resurrect *)
  Entity_manager.destroy_entity mgr e;
  Alcotest.(check bool) "still dead" false (Entity_manager.is_alive mgr e)

let test_growth_preserves_alive () =
  let mgr = Entity_manager.create 2 in
  let e1 = Entity_manager.create_entity mgr in
  let e2 = Entity_manager.create_entity mgr in
  ignore (Entity_manager.create_entity mgr); (* triggers resize *)
  Alcotest.(check bool) "still alive after grow"
    true (Entity_manager.is_alive mgr e1 && Entity_manager.is_alive mgr e2)

let test_set_component () =
  let mgr = Entity_manager.create 4 in
  let registry = Component_registry.create () in
  let position = Component_registry.register registry ~name:"Position" ~id:0 in
  let comp = Component.Component position in
  (* prepare sparse-set backing via component registration *)
  let entity = Entity_manager.create_entity mgr in
  (* first set should behave like add *)
  Entity_manager.set_component mgr entity comp (Obj.repr (1, 1));
  let value =
    Entity_manager.get_component mgr entity comp
    |> Option.map Obj.magic
  in
  Alcotest.(check (option @@ pair int int)) "initial set" (Some (1, 1)) value;

  (* second set overrides without changing count *)
  Entity_manager.set_component mgr entity comp (Obj.repr (2, 3));
  let updated =
    Entity_manager.get_component mgr entity comp
    |> Option.map Obj.magic
  in
  Alcotest.(check (option @@ pair int int)) "set overrides" (Some (2, 3)) updated

let tests =
  [
    Alcotest.test_case "create and destroy" `Quick test_create_and_destroy;
    Alcotest.test_case "reuse id" `Quick test_reuse_id;
    Alcotest.test_case "capacity growth" `Quick test_capacity_growth;
    Alcotest.test_case "deterministic allocation" `Quick test_deterministic_allocation;
    Alcotest.test_case "invalid destroy" `Quick test_invalid_destroy;
    Alcotest.test_case "growth preserves alive" `Quick test_growth_preserves_alive;
    Alcotest.test_case "set component" `Quick test_set_component;
  ]

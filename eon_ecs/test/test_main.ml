open Alcotest

let () =
  run "Eon ECS Test Suite"
    [
      "Entity Manager", Test_entity_manager.tests;
    ]

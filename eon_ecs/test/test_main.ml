open Alcotest

let () =
  run "Eon ECS Test Suite"
    [
      "Entity Manager", Test_entity_manager.tests;
      "Sparse Set", Test_sparse_set.tests;
      "Entity ID", Test_entity_id.tests;
      "Component Registry", Test_component_registry.tests;
      "Resource Store", Test_resource_store.tests;
      "Buses", Test_bus.tests;
      "Systems", Test_system.tests;
      "Pipeline", Test_pipeline.tests;
      "Query", Test_query.tests
    ]

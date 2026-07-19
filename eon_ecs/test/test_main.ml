open Alcotest

let () =
  run "Eon ECS Test Suite"
    [
      "Entity Manager", Test_entity_manager.tests;
      "Entity Manager (QCheck)", Test_prop_entity_manager.tests;
      "Sparse Set", Test_sparse_set.tests;
      "Sparse Set (QCheck)", Test_prop_sparse_set.tests;
      "Entity ID", Test_entity_id.tests;
      "Component Registry", Test_component_registry.tests;
      "Component", Test_component.tests;
      "Resource Store", Test_resource_store.tests;
      "Buses", Test_bus.tests;
      "Buses (QCheck)", Test_prop_bus.tests;
      "Buses.Make/Default", Test_buses.tests;
      "Systems", Test_system.tests;
      "Dependency_graph", Test_dependency_graph.tests;
      "Pipeline", Test_pipeline.tests;
      "Pipeline (QCheck)", Test_prop_pipeline.tests;
      "Query", Test_query.tests;
      "Query.iter_entities", Test_query.iter_entities_tests;
      "Progress", Test_progress.tests;
      "Progress (QCheck)", Test_prop_progress.tests;
      "Loop", Test_loop.tests;
      "Loop (QCheck)", Test_prop_loop.tests;
      "World", Test_world.tests;
      "World (QCheck)", Test_prop_world.tests;
      "Clock", Test_clock.tests;
    ]

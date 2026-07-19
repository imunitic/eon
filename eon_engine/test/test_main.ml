module Test_api_structure = struct
  let tests = Test_api_structure.tests
end

module Test_world = struct
  let tests = Test_world.tests
end

let () =
  Alcotest.run "Eon Engine Test Suite" [
    ("Components", Test_components.tests);
    ("Query", Test_query.tests);
    ("View", Test_view.tests);
    ("API Structure", Test_api_structure.tests);
    ("World", Test_world.tests);
    ("Pipeline", Test_pipeline.tests);
    ("Executor", Test_executor.tests);
    ("Executor (QCheck)", Test_prop_executor.tests);
    ("Input", Test_input.tests);
    ("Audio", Test_audio.tests);
    ("Math", Test_math.tests);
    ("Math properties", Test_prop_math.tests);
    ("Resource and Service", Test_resource_service.tests);
    ("Render stream", Test_render_stream.tests);
    ("Render stream properties", Test_prop_render_stream.tests);
    ("Render modules", Test_render_modules.tests);
    ("Transform system", Test_transform_system.tests);
    ("Transform system (QCheck)", Test_prop_transform_system.tests);
    ("Lifecycle system", Test_lifecycle_system.tests);
    ("Transform hierarchy", Test_transform_hierarchy.tests);
    ("Time", Test_time.tests);
    ("Prefab", Test_prefab.tests);
    ("Prefab properties", Test_prop_prefab.tests);
  ]

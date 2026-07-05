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
    ("API Structure", Test_api_structure.tests);
    ("World", Test_world.tests);
    ("Pipeline", Test_pipeline.tests);
    ("Executor", Test_executor.tests);
    ("Input", Test_input.tests);
    ("Audio", Test_audio.tests);
    ("Math", Test_math.tests);
    ("Math properties", Test_prop_math.tests);
    ("Render stream", Test_render_stream.tests);
    ("Render stream properties", Test_prop_render_stream.tests);
    ("Render modules", Test_render_modules.tests);
  ]

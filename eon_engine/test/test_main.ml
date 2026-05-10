module Test_api_structure = struct
  let tests = Test_api_structure.tests
end

let () =
  Alcotest.run "Eon Engine Test Suite" [
    ("Components", Test_components.tests);
    ("Query", Test_query.tests);
    ("API Structure", Test_api_structure.tests);
  ]

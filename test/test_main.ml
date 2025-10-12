let () =
  Alcotest.run "Eon Test Suite"
    [
      "Entity_manager", Test_entity_manager.tests;
    ]

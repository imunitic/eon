let () =
  Alcotest.run "Eon Engine Test Suite" [
    "Components", Test_components.tests;
    "Query", Test_query.tests;
  ]
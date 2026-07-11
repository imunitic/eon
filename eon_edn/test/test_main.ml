open Alcotest

let () =
  run "Eon EDN Test Suite"
    [
      "Edn_parser", Test_edn_parser.tests;
      "Edn_middleware", Test_edn_middleware.tests;
      "Property tests", Test_prop_edn.tests;
    ]

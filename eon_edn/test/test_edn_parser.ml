open Alcotest
open Eon_edn.Edn_effects

let parse s = Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value s

let value_testable =
  let rec pp fmt v =
    match v with
    | VNil -> Format.fprintf fmt "VNil"
    | VBool b -> Format.fprintf fmt "VBool %b" b
    | VNumber n -> Format.fprintf fmt "VNumber %g" n
    | VString s -> Format.fprintf fmt "VString %S" s
    | VSymbol s -> Format.fprintf fmt "VSymbol %S" s
    | VKeyword s -> Format.fprintf fmt "VKeyword %S" s
    | VList vs -> Format.fprintf fmt "VList [%a]" (Format.pp_print_list pp) vs
    | VVector vs -> Format.fprintf fmt "VVector [%a]" (Format.pp_print_list pp) vs
    | VMap kvs ->
        Format.fprintf fmt "VMap [%a]"
          (Format.pp_print_list (fun fmt (k, v) -> Format.fprintf fmt "(%a, %a)" pp k pp v))
          kvs
    | VTagged (t, v) -> Format.fprintf fmt "VTagged (%S, %a)" t pp v
    | VMeta (m, v) -> Format.fprintf fmt "VMeta (%a, %a)" pp m pp v
  in
  testable pp ( = )

let check_value = check value_testable

let test_primitives () =
  check_value "nil" VNil (parse "nil");
  check_value "true" (VBool true) (parse "true");
  check_value "false" (VBool false) (parse "false");
  check_value "positive int" (VNumber 42.0) (parse "42");
  check_value "negative int" (VNumber (-7.0)) (parse "-7");
  check_value "float" (VNumber 3.5) (parse "3.5");
  check_value "symbol" (VSymbol "foo") (parse "foo");
  check_value "keyword" (VKeyword "foo") (parse ":foo")

let test_string_escapes () =
  check_value "plain string" (VString "hello") (parse {|"hello"|});
  check_value "newline escape" (VString "a\nb") (parse {|"a\nb"|});
  check_value "tab escape" (VString "a\tb") (parse {|"a\tb"|});
  check_value "quote escape" (VString "a\"b") (parse {|"a\"b"|})

let test_collections () =
  check_value "empty list" (VList []) (parse "()");
  check_value "list" (VList [ VNumber 1.0; VNumber 2.0 ]) (parse "(1 2)");
  check_value "empty vector" (VVector []) (parse "[]");
  check_value "vector" (VVector [ VNumber 1.0; VNumber 2.0 ]) (parse "[1 2]");
  check_value "empty map" (VMap []) (parse "{}");
  check_value "map"
    (VMap [ (VKeyword "a", VNumber 1.0) ])
    (parse "{:a 1}");
  check_value "nested"
    (VMap [ (VKeyword "pos", VVector [ VNumber 1.0; VNumber 2.0 ]) ])
    (parse "{:pos [1 2]}")

let test_whitespace_and_commas () =
  check_value "commas as whitespace" (VVector [ VNumber 1.0; VNumber 2.0 ]) (parse "[1, 2]");
  check_value "extra whitespace"
    (VMap [ (VKeyword "a", VNumber 1.0) ])
    (parse "  {  :a   1  }  ")

let test_tagged_default () =
  let v = Eon_edn.Edn_middleware.run_with_middleware
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  check_value "unregistered tag wraps as VTagged" (VTagged ("uuid", VString "abc")) v

let test_tagged_registered () =
  Eon_edn.Edn_middleware.register_tag_handler "double" (fun _ v ->
      match v with VNumber n -> VNumber (n *. 2.0) | v -> v);
  let v = Eon_edn.Edn_middleware.run_with_middleware
      (fun () -> Eon_edn.Edn_parser.value ())
      "#double 21"
  in
  check_value "registered tag transforms value" (VNumber 42.0) v

let test_meta () =
  let v = Eon_edn.Edn_middleware.run_with_middleware
      (fun () -> Eon_edn.Edn_parser.value ())
      {|^:foo {:a 1}|}
  in
  check_value "meta wraps value"
    (VMeta (VKeyword "foo", VMap [ (VKeyword "a", VNumber 1.0) ]))
    v

let test_unterminated_errors () =
  (try
     ignore (parse "(1 2");
     fail "expected failure on unterminated list"
   with Failure _ -> ());
  (try
     ignore (parse "[1 2");
     fail "expected failure on unterminated vector"
   with Failure _ -> ());
  (try
     ignore (parse "{:a 1");
     fail "expected failure on unterminated map"
   with Failure _ -> ())

let tests = [
  test_case "primitives" `Quick test_primitives;
  test_case "string escapes" `Quick test_string_escapes;
  test_case "collections" `Quick test_collections;
  test_case "whitespace and commas" `Quick test_whitespace_and_commas;
  test_case "tagged value (default)" `Quick test_tagged_default;
  test_case "tagged value (registered handler)" `Quick test_tagged_registered;
  test_case "meta value" `Quick test_meta;
  test_case "unterminated collections raise" `Quick test_unterminated_errors;
]

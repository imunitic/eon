open Alcotest
open Eon_edn.Edn_effects
open Eon_edn.Edn_middleware

let register_uuid () =
  register_tag_handler "uuid" (fun _ v ->
      match v with
      | VString s -> VTagged ("uuid", VString (String.uppercase_ascii s))
      | v -> v)

(* An "observing" handler shaped like [log_tags] but recording to a ref
   instead of printing, so composition/forwarding can be asserted on
   directly instead of via stdout capture. *)
let observing (seen : string list ref) : handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff ->
      match eff with
      | Tag (t, _) -> seen := t :: !seen; None
      | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

let test_default_handler_resolves_via_registry () =
  register_uuid ();
  let v =
    run_with_middleware
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  check bool "resolved to uppercased uuid via registry"
    true
    (v = VTagged ("uuid", VString "ABC"))

let test_middleware_forwards_and_observes () =
  register_uuid ();
  let seen = ref [] in
  let v =
    run_with_middleware
      ~handlers:[ observing seen; strict_tags [ "uuid"; "inst" ] ]
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  check bool "observing handler saw the tag" true (!seen = [ "uuid" ]);
  check bool "value still resolved through default_handler" true
    (v = VTagged ("uuid", VString "ABC"))

let test_strict_tags_rejects () =
  let raised =
    try
      let _ =
        run_with_middleware
          ~handlers:[ strict_tags [ "inst" ] ]
          (fun () -> Eon_edn.Edn_parser.value ())
          {|#uuid "xyz"|}
      in
      false
    with Failure msg -> msg = "Unknown tag: #uuid"
  in
  check bool "strict_tags rejects a disallowed tag" true raised

let test_strict_tags_allows () =
  register_uuid ();
  let v =
    run_with_middleware
      ~handlers:[ strict_tags [ "uuid" ] ]
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  check bool "allowed tag still resolves" true (v = VTagged ("uuid", VString "ABC"))

let test_log_tags_does_not_swallow () =
  register_uuid ();
  (* log_tags must forward, not consume — value still resolves via
     default_handler even with log_tags in the chain. This is the exact
     bug class found and fixed during design: a handler that always
     returns [Some] permanently shadows everything behind it. *)
  let v =
    run_with_middleware
      ~handlers:[ log_tags ]
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  check bool "log_tags forwards, does not swallow" true (v = VTagged ("uuid", VString "ABC"))

let parse_text input () = Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value input

let test_reify_ignores_registry () =
  register_uuid ();
  let v = with_middleware ~handlers:[ reify ] (parse_text {|#uuid "abc"|}) in
  check bool "tag left unresolved despite a registered handler" true
    (v = VTagged ("uuid", VString "abc"))

let test_reify_nested_and_meta () =
  let nested = with_middleware ~handlers:[ reify ] (parse_text {|#a #b 1|}) in
  check bool "nested tags reified bottom-up" true
    (nested = VTagged ("a", VTagged ("b", VNumber 1.)));
  let meta_text = {|^:m [1]|} in
  let reified = with_middleware ~handlers:[ reify ] (parse_text meta_text) in
  let default =
    run_with_middleware (fun () -> Eon_edn.Edn_parser.value ()) meta_text
  in
  check bool "meta reified like default_meta" true (reified = default)

let test_with_middleware_matches_run () =
  register_uuid ();
  let text = {|[#uuid "abc" #other 1]|} in
  let via_run =
    run_with_middleware ~handlers:[ strict_tags [ "uuid"; "other" ] ]
      (fun () -> Eon_edn.Edn_parser.value ()) text
  in
  let via_with =
    with_middleware ~handlers:[ strict_tags [ "uuid"; "other" ] ] (parse_text text)
  in
  check bool "with_middleware = run_with_middleware" true (via_run = via_with)

let tests = [
  test_case "reify ignores the tag registry" `Quick test_reify_ignores_registry;
  test_case "reify handles nested tags and meta" `Quick test_reify_nested_and_meta;
  test_case "with_middleware matches run_with_middleware" `Quick test_with_middleware_matches_run;
  test_case "default_handler resolves via registry" `Quick test_default_handler_resolves_via_registry;
  test_case "middleware chain forwards and observes" `Quick test_middleware_forwards_and_observes;
  test_case "strict_tags rejects disallowed tag" `Quick test_strict_tags_rejects;
  test_case "strict_tags allows listed tag" `Quick test_strict_tags_allows;
  test_case "log_tags does not swallow the effect" `Quick test_log_tags_does_not_swallow;
]

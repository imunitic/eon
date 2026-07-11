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

let tests = [
  test_case "default_handler resolves via registry" `Quick test_default_handler_resolves_via_registry;
  test_case "middleware chain forwards and observes" `Quick test_middleware_forwards_and_observes;
  test_case "strict_tags rejects disallowed tag" `Quick test_strict_tags_rejects;
  test_case "strict_tags allows listed tag" `Quick test_strict_tags_allows;
  test_case "log_tags does not swallow the effect" `Quick test_log_tags_does_not_swallow;
]

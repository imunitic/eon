open Eon_engine

(* ------------------------------------------------------------------ *)
(* Color                                                               *)
(* ------------------------------------------------------------------ *)

let test_color_create () =
  let c = Color.create 0.1 0.2 0.3 0.4 in
  Alcotest.(check (float 1e-9)) "r" 0.1 c.r;
  Alcotest.(check (float 1e-9)) "g" 0.2 c.g;
  Alcotest.(check (float 1e-9)) "b" 0.3 c.b;
  Alcotest.(check (float 1e-9)) "a" 0.4 c.a

let test_color_white () =
  Alcotest.(check (float 1e-9)) "white r" 1.0 Color.white.r;
  Alcotest.(check (float 1e-9)) "white g" 1.0 Color.white.g;
  Alcotest.(check (float 1e-9)) "white b" 1.0 Color.white.b;
  Alcotest.(check (float 1e-9)) "white a" 1.0 Color.white.a

let test_color_black () =
  Alcotest.(check (float 1e-9)) "black r" 0.0 Color.black.r;
  Alcotest.(check (float 1e-9)) "black g" 0.0 Color.black.g;
  Alcotest.(check (float 1e-9)) "black b" 0.0 Color.black.b;
  Alcotest.(check (float 1e-9)) "black a" 1.0 Color.black.a

let test_color_transparent () =
  Alcotest.(check (float 1e-9)) "transparent a" 0.0 Color.transparent.a;
  Alcotest.(check (float 1e-9)) "transparent r" 0.0 Color.transparent.r

(* ------------------------------------------------------------------ *)
(* Rendering_result                                                    *)
(* ------------------------------------------------------------------ *)

let test_result_empty_has_no_errors () =
  Alcotest.(check bool) "empty has no errors" false
    (Rendering_result.has_errors Rendering_result.empty)

let test_result_empty_list_is_empty () =
  Alcotest.(check (list string)) "empty errors list" []
    Rendering_result.empty.errors

let test_result_with_errors () =
  let r = { Rendering_result.errors = ["missing texture"; "bad font"] } in
  Alcotest.(check bool)  "has_errors true"  true  (Rendering_result.has_errors r);
  Alcotest.(check int)   "two errors"       2     (List.length r.errors)

(* ------------------------------------------------------------------ *)
(* Rendering_backend.Null                                              *)
(* ------------------------------------------------------------------ *)

let test_null_init_is_noop () =
  Rendering_backend.Null.init ();
  Alcotest.(check pass) "init is noop" () ()

let test_null_render_returns_empty () =
  let stream = Render_stream.create () in
  let result = Rendering_backend.Null.render stream ~dt:0.016 in
  Alcotest.(check bool) "render returns empty result" false
    (Rendering_result.has_errors result)

let test_null_diagnostics_empty () =
  Alcotest.(check int) "diagnostics empty" 0
    (List.length (Rendering_backend.Null.diagnostics ()))

let test_null_shutdown_is_noop () =
  Rendering_backend.Null.shutdown ();
  Alcotest.(check pass) "shutdown is noop" () ()

(* ------------------------------------------------------------------ *)
(* Loop.step — render integration                                      *)
(* ------------------------------------------------------------------ *)

module Recording_renderer = struct
  type command = Render_commands.command

  let render_called  = ref false
  let last_dt        = ref 0.0

  let init ()              = render_called := false; last_dt := 0.0
  let render _stream ~dt   = render_called := true; last_dt := dt;
                             Rendering_result.empty
  let diagnostics ()       = []
  let shutdown ()          = render_called := false
end

module Test_platform = struct
  type t = [ `Test ]
  module Input_backend     = Input_backend.Scripted
  module Audio_backend     = Audio_backend.Null
  module Rendering_backend = Recording_renderer
end

module My_progress = Progress.Make (Pipeline.Default)
module My_loop =
  Loop.Make (Eon_ecs.Clock.Mtime) (My_progress) (Test_platform) (Loop_buses)

let make_world_with_stream () =
  let world  = World.create () in
  let stream = Render_stream.create () in
  Render_stream.add_world stream (`Clear_background Color.black);
  World.set_data world `Render_stream stream;
  world

let test_loop_calls_render_when_stream_present () =
  Input_backend.Scripted.set_frames [Raw_input_frame.empty; Raw_input_frame.empty];
  Recording_renderer.render_called := false;
  let world    = make_world_with_stream () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  let _ = My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
    ~should_continue:(fun _ -> false) in
  Alcotest.(check bool) "render was called" true !Recording_renderer.render_called

let test_loop_passes_dt_to_render () =
  Input_backend.Scripted.set_frames [Raw_input_frame.empty; Raw_input_frame.empty];
  Recording_renderer.last_dt := 0.0;
  let world    = make_world_with_stream () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  let _ = My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
    ~should_continue:(fun _ -> false) in
  Alcotest.(check (float 1e-9)) "dt passed to render" 0.016 !Recording_renderer.last_dt

let test_loop_no_stream_does_not_call_render () =
  Input_backend.Scripted.set_frames [Raw_input_frame.empty];
  Recording_renderer.render_called := false;
  let world    = World.create () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  let _ = My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
    ~should_continue:(fun _ -> false) in
  Alcotest.(check bool) "render not called when no stream" false
    !Recording_renderer.render_called

(* ------------------------------------------------------------------ *)
(* Suite                                                               *)
(* ------------------------------------------------------------------ *)

let tests = [
  "Color — create round-trips",             `Quick, test_color_create;
  "Color — white",                          `Quick, test_color_white;
  "Color — black",                          `Quick, test_color_black;
  "Color — transparent alpha is 0",         `Quick, test_color_transparent;
  "Rendering_result — empty has no errors", `Quick, test_result_empty_has_no_errors;
  "Rendering_result — empty list",          `Quick, test_result_empty_list_is_empty;
  "Rendering_result — with errors",         `Quick, test_result_with_errors;
  "Rendering_backend.Null — init is noop",  `Quick, test_null_init_is_noop;
  "Rendering_backend.Null — render empty",  `Quick, test_null_render_returns_empty;
  "Rendering_backend.Null — diagnostics",   `Quick, test_null_diagnostics_empty;
  "Rendering_backend.Null — shutdown noop", `Quick, test_null_shutdown_is_noop;
  "Loop.step — calls render with stream",   `Quick, test_loop_calls_render_when_stream_present;
  "Loop.step — passes dt to render",        `Quick, test_loop_passes_dt_to_render;
  "Loop.step — no stream skips render",     `Quick, test_loop_no_stream_does_not_call_render;
]

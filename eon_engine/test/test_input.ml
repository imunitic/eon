open Eon_engine

(* ------------------------------------------------------------------ *)
(* Raw_input_frame.empty                                               *)
(* ------------------------------------------------------------------ *)

let test_empty_keys () =
  let f = Raw_input_frame.empty in
  Alcotest.(check bool) "keys_down empty"     true (Key.Set.is_empty f.keys_down);
  Alcotest.(check bool) "keys_pressed empty"  true (Key.Set.is_empty f.keys_pressed);
  Alcotest.(check bool) "keys_released empty" true (Key.Set.is_empty f.keys_released)

let test_empty_mouse () =
  let f = Raw_input_frame.empty in
  Alcotest.(check bool) "mouse_buttons_down empty"
    true (Mouse_button.Set.is_empty f.mouse_buttons_down);
  Alcotest.(check (pair int int)) "mouse_screen" (0, 0) f.mouse_screen;
  Alcotest.(check (pair int int)) "mouse_delta"  (0, 0) f.mouse_delta;
  Alcotest.(check (option string)) "text_input" None f.text_input

let test_empty_gamepad () =
  let f = Raw_input_frame.empty in
  Alcotest.(check bool) "no gamepad" true (Option.is_none f.gamepad);
  Alcotest.(check (list (Alcotest.testable (fun _ _ -> ()) (=)))) "events" [] f.events

(* ------------------------------------------------------------------ *)
(* Input_backend.Scripted                                              *)
(* ------------------------------------------------------------------ *)

let scripted_frame k =
  { Raw_input_frame.empty with
    keys_pressed = Key.Set.singleton k }

let test_scripted_sequence () =
  let f1 = scripted_frame Key.A in
  let f2 = scripted_frame Key.B in
  let f3 = scripted_frame Key.C in
  Input_backend.Scripted.set_frames [f1; f2; f3];
  let r1 = Input_backend.Scripted.collect () in
  let r2 = Input_backend.Scripted.collect () in
  let r3 = Input_backend.Scripted.collect () in
  Alcotest.(check bool) "frame 1 has A" true
    (Key.Set.mem Key.A r1.keys_pressed);
  Alcotest.(check bool) "frame 2 has B" true
    (Key.Set.mem Key.B r2.keys_pressed);
  Alcotest.(check bool) "frame 3 has C" true
    (Key.Set.mem Key.C r3.keys_pressed)

let test_scripted_exhausted () =
  Input_backend.Scripted.set_frames [];
  let r = Input_backend.Scripted.collect () in
  Alcotest.(check bool) "exhausted → empty" true
    (Key.Set.is_empty r.keys_pressed)

let test_scripted_shutdown_clears () =
  Input_backend.Scripted.set_frames [scripted_frame Key.Space];
  Input_backend.Scripted.shutdown ();
  let r = Input_backend.Scripted.collect () in
  Alcotest.(check bool) "after shutdown → empty" true
    (Key.Set.is_empty r.keys_pressed)

(* ------------------------------------------------------------------ *)
(* Integration: Raw_input_frame written to world by Loop.step          *)
(* ------------------------------------------------------------------ *)

module Test_platform = struct
  type t = [ `Test ]
  module Input_backend     = Input_backend.Scripted
  module Audio_backend     = Audio_backend.Null
  module Rendering_backend = Rendering_backend.Null
end

module My_progress = Progress.Make (Pipeline.Default)
module My_loop =
  Loop.Make (Eon_ecs.Clock.Mtime) (My_progress) (Test_platform) (Loop_buses)

let test_loop_writes_input_to_world () =
  let frame = scripted_frame Key.Enter in
  Input_backend.Scripted.set_frames [frame; Raw_input_frame.empty];
  let world    = World.create () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  let world, _, _ =
    My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
      ~should_continue:(fun _ -> false)
  in
  let result = Raw_input_frame.get world in
  Alcotest.(check bool) "frame present" true (Option.is_some result);
  let f = Option.get result in
  Alcotest.(check bool) "Enter key pressed" true
    (Key.Set.mem Key.Enter f.keys_pressed)

let test_loop_updates_each_tick () =
  let f1 = scripted_frame Key.Left in
  let f2 = scripted_frame Key.Right in
  Input_backend.Scripted.set_frames [f1; f2];
  let world    = World.create () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  (* First tick *)
  let world, t1, _ =
    My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
      ~should_continue:(fun _ -> false)
  in
  let after_tick1 = Raw_input_frame.get world in
  (* Second tick *)
  let world, _, _ =
    My_loop.step ~progress ~world ~last_time:t1 ~now:0.032
      ~should_continue:(fun _ -> false)
  in
  let after_tick2 = Raw_input_frame.get world in
  Alcotest.(check bool) "tick 1: Left"  true
    (Key.Set.mem Key.Left  (Option.get after_tick1).keys_pressed);
  Alcotest.(check bool) "tick 2: Right" true
    (Key.Set.mem Key.Right (Option.get after_tick2).keys_pressed)

(* ------------------------------------------------------------------ *)
(* Suite                                                               *)
(* ------------------------------------------------------------------ *)

let tests = [
  "Raw_input_frame.empty — keys",    `Quick, test_empty_keys;
  "Raw_input_frame.empty — mouse",   `Quick, test_empty_mouse;
  "Raw_input_frame.empty — gamepad", `Quick, test_empty_gamepad;
  "Scripted — frame sequence",       `Quick, test_scripted_sequence;
  "Scripted — exhausted returns empty", `Quick, test_scripted_exhausted;
  "Scripted — shutdown clears frames",  `Quick, test_scripted_shutdown_clears;
  "Loop.step — writes frame to world",  `Quick, test_loop_writes_input_to_world;
  "Loop.step — updates frame each tick", `Quick, test_loop_updates_each_tick;
]

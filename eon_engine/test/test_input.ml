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

let test_empty_touch () =
  let f = Raw_input_frame.empty in
  Alcotest.(check bool) "touches_down empty"
    true (Touch_id.Map.is_empty f.touches_down);
  Alcotest.(check bool) "touches_pressed empty"
    true (Touch_id.Set.is_empty f.touches_pressed);
  Alcotest.(check bool) "touches_released empty"
    true (Touch_id.Map.is_empty f.touches_released);
  Alcotest.(check bool) "touches_cancelled empty"
    true (Touch_id.Map.is_empty f.touches_cancelled)

(* ------------------------------------------------------------------ *)
(* Touch_id                                                            *)
(* ------------------------------------------------------------------ *)

let test_touch_id_roundtrip () =
  Alcotest.(check int) "of_int/to_int" 7 (Touch_id.to_int (Touch_id.of_int 7))

let test_touch_id_set_map () =
  let a = Touch_id.of_int 1 and b = Touch_id.of_int 2 in
  let s = Touch_id.Set.of_list [a; b; a] in
  Alcotest.(check int) "set dedups" 2 (Touch_id.Set.cardinal s);
  let m = Touch_id.Map.(empty |> add a "x" |> add b "y") in
  Alcotest.(check (option string)) "map find" (Some "y") (Touch_id.Map.find_opt b m);
  Alcotest.(check bool) "distinct ids compare unequal" true
    (Touch_id.compare a b <> 0)

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

let test_scripted_set_frames_replaces_not_appends () =
  Input_backend.Scripted.set_frames [ scripted_frame Key.A; scripted_frame Key.B ];
  let r1 = Input_backend.Scripted.collect () in
  Alcotest.(check bool) "first frame is A" true (Key.Set.mem Key.A r1.keys_pressed);
  (* [B] is still queued at this point — replacing now must discard it, not
     queue [C] behind it. *)
  Input_backend.Scripted.set_frames [ scripted_frame Key.C ];
  let r2 = Input_backend.Scripted.collect () in
  Alcotest.(check bool) "replaced sequence yields C, not the discarded B" true
    (Key.Set.mem Key.C r2.keys_pressed);
  let r3 = Input_backend.Scripted.collect () in
  Alcotest.(check bool) "replaced sequence is exhausted after its one frame" true
    (Key.Set.is_empty r3.keys_pressed)

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
  let result = Raw_input_frame.fetch_opt world in
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
  let after_tick1 = Raw_input_frame.fetch_opt world in
  (* Second tick *)
  let world, _, _ =
    My_loop.step ~progress ~world ~last_time:t1 ~now:0.032
      ~should_continue:(fun _ -> false)
  in
  let after_tick2 = Raw_input_frame.fetch_opt world in
  Alcotest.(check bool) "tick 1: Left"  true
    (Key.Set.mem Key.Left  (Option.get after_tick1).keys_pressed);
  Alcotest.(check bool) "tick 2: Right" true
    (Key.Set.mem Key.Right (Option.get after_tick2).keys_pressed)

(* ------------------------------------------------------------------ *)
(* Touch frames through Scripted and Loop.step                         *)
(* ------------------------------------------------------------------ *)

let touch ?(delta = (0.0, 0.0)) ?(pressure = 1.0) ?(radius = 0.0) position =
  { Raw_input_frame.position; delta; pressure; radius }

let id = Touch_id.of_int

let two_finger_frame =
  let t1 = touch (10.0, 20.0) and t2 = touch ~pressure:0.5 ~radius:4.0 (300.5, 40.25) in
  { Raw_input_frame.empty with
    touches_down    = Touch_id.Map.(empty |> add (id 1) t1 |> add (id 2) t2);
    touches_pressed = Touch_id.Set.singleton (id 2);
    events          = [ Raw_input_frame.Touch_down (id 2, (300.5, 40.25), 0.5) ] }

let release_frame =
  { Raw_input_frame.empty with
    touches_down     = Touch_id.Map.singleton (id 1) (touch (12.0, 22.0));
    touches_released = Touch_id.Map.singleton (id 2) (touch (301.0, 41.0));
    events           = [ Raw_input_frame.Touch_up (id 2, (301.0, 41.0), 0.25) ] }

let test_scripted_touch_frames () =
  Input_backend.Scripted.set_frames [ two_finger_frame; release_frame ];
  let r1 = Input_backend.Scripted.collect () in
  let r2 = Input_backend.Scripted.collect () in
  Alcotest.(check int) "two fingers down" 2 (Touch_id.Map.cardinal r1.touches_down);
  Alcotest.(check bool) "finger 2 pressed" true
    (Touch_id.Set.mem (id 2) r1.touches_pressed);
  Alcotest.(check bool) "finger 1 not pressed" false
    (Touch_id.Set.mem (id 1) r1.touches_pressed);
  let t2 = Touch_id.Map.find (id 2) r1.touches_down in
  Alcotest.(check (float 1e-9)) "pressure kept" 0.5 t2.pressure;
  Alcotest.(check (float 1e-9)) "radius kept" 4.0 t2.radius;
  Alcotest.(check bool) "finger 2 released, with final position" true
    (match Touch_id.Map.find_opt (id 2) r2.touches_released with
     | Some t -> t.position = (301.0, 41.0)
     | None -> false);
  Alcotest.(check bool) "finger 2 no longer down" false
    (Touch_id.Map.mem (id 2) r2.touches_down)

let test_loop_writes_touch_to_world () =
  Input_backend.Scripted.set_frames [ two_finger_frame ];
  let world    = World.create () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  let world, _, _ =
    My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
      ~should_continue:(fun _ -> false)
  in
  let f = Raw_input_frame.fetch world in
  Alcotest.(check int) "two touches reach the world" 2
    (Touch_id.Map.cardinal f.touches_down);
  Alcotest.(check bool) "distinct ids keep distinct positions" true
    ((Touch_id.Map.find (id 1) f.touches_down).position
     <> (Touch_id.Map.find (id 2) f.touches_down).position)

(* ------------------------------------------------------------------ *)
(* Suite                                                               *)
(* ------------------------------------------------------------------ *)

let tests = [
  "Raw_input_frame.empty — keys",    `Quick, test_empty_keys;
  "Raw_input_frame.empty — mouse",   `Quick, test_empty_mouse;
  "Raw_input_frame.empty — gamepad", `Quick, test_empty_gamepad;
  "Raw_input_frame.empty — touch",   `Quick, test_empty_touch;
  "Touch_id — of_int/to_int",        `Quick, test_touch_id_roundtrip;
  "Touch_id — Set and Map",          `Quick, test_touch_id_set_map;
  "Scripted — touch frames",         `Quick, test_scripted_touch_frames;
  "Loop.step — writes touch frame to world", `Quick, test_loop_writes_touch_to_world;
  "Scripted — frame sequence",       `Quick, test_scripted_sequence;
  "Scripted — exhausted returns empty", `Quick, test_scripted_exhausted;
  "Scripted — set_frames replaces rather than appends", `Quick,
    test_scripted_set_frames_replaces_not_appends;
  "Scripted — shutdown clears frames",  `Quick, test_scripted_shutdown_clears;
  "Loop.step — writes frame to world",  `Quick, test_loop_writes_input_to_world;
  "Loop.step — updates frame each tick", `Quick, test_loop_updates_each_tick;
]

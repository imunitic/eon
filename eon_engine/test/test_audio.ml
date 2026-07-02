open Eon_engine

(* ------------------------------------------------------------------ *)
(* Audio_command_buffer                                                *)
(* ------------------------------------------------------------------ *)

let test_create_empty () =
  let buf = Audio_command_buffer.create () in
  Alcotest.(check (list (Alcotest.testable (fun _ _ -> ()) (=))))
    "new buffer is empty" [] (Audio_command_buffer.to_list buf)

let test_add_preserves_order () =
  let buf = Audio_command_buffer.create () in
  let c1  = Audio_command.Stop_all in
  let c2  = Audio_command.Pause_all in
  let c3  = Audio_command.Resume_all in
  Audio_command_buffer.add buf c1;
  Audio_command_buffer.add buf c2;
  Audio_command_buffer.add buf c3;
  Alcotest.(check (list (Alcotest.testable (fun _ _ -> ()) (=))))
    "commands in insertion order" [c1; c2; c3]
    (Audio_command_buffer.to_list buf)

let test_clear_empties_buffer () =
  let buf = Audio_command_buffer.create () in
  Audio_command_buffer.add buf Audio_command.Stop_all;
  Audio_command_buffer.clear buf;
  Alcotest.(check (list (Alcotest.testable (fun _ _ -> ()) (=))))
    "cleared buffer is empty" [] (Audio_command_buffer.to_list buf)

(* ------------------------------------------------------------------ *)
(* Audio_backend.Null                                                  *)
(* ------------------------------------------------------------------ *)

let test_null_init_is_noop () =
  Audio_backend.Null.init (module Asset_lookup.Null);
  Alcotest.(check pass) "init is a noop" () ()

let test_null_submit_is_noop () =
  Audio_backend.Null.submit [Audio_command.Stop_all; Audio_command.Pause_all];
  Alcotest.(check pass) "submit is a noop" () ()

let test_null_shutdown_is_noop () =
  Audio_backend.Null.shutdown ();
  Alcotest.(check pass) "shutdown is a noop" () ()

(* ------------------------------------------------------------------ *)
(* Integration: Audio_command_buffer written and cleared by Loop.step  *)
(* ------------------------------------------------------------------ *)

module Test_platform = struct
  type t = [ `Test ]
  module Input_backend = Input_backend.Scripted

  (* Capture what gets submitted so we can assert on it *)
  let submitted : Audio_command.t list ref = ref []

  module Audio_backend = struct
    let init _assets   = submitted := []
    let submit cmds    = submitted := cmds
    let shutdown ()    = submitted := []
  end
end

module My_progress = Progress.Make (Pipeline.Default)
module My_loop =
  Loop.Make (Eon_ecs.Clock.Mtime) (My_progress) (Test_platform) (Loop_buses)

let make_world_with_buf () =
  let world = World.create () in
  let buf   = Audio_command_buffer.create () in
  Audio_command_buffer.set world buf;
  world

let test_loop_submits_commands () =
  Input_backend.Scripted.set_frames [Raw_input_frame.empty; Raw_input_frame.empty];
  let world    = make_world_with_buf () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  (* Add a command to the buffer before step *)
  (match Audio_command_buffer.get world with
   | Some buf -> Audio_command_buffer.add buf Audio_command.Stop_all
   | None -> ());
  let _world, _, _ =
    My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
      ~should_continue:(fun _ -> false)
  in
  Alcotest.(check (list (Alcotest.testable (fun _ _ -> ()) (=))))
    "submitted commands match" [Audio_command.Stop_all]
    !Test_platform.submitted

let test_loop_clears_buffer_after_submit () =
  Input_backend.Scripted.set_frames [Raw_input_frame.empty; Raw_input_frame.empty];
  let world    = make_world_with_buf () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  (match Audio_command_buffer.get world with
   | Some buf -> Audio_command_buffer.add buf Audio_command.Pause_all
   | None -> ());
  let world, _, _ =
    My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
      ~should_continue:(fun _ -> false)
  in
  let remaining =
    Option.map Audio_command_buffer.to_list (Audio_command_buffer.get world)
  in
  Alcotest.(check (option (list (Alcotest.testable (fun _ _ -> ()) (=)))))
    "buffer cleared after step" (Some []) remaining

let test_loop_no_buffer_is_safe () =
  Input_backend.Scripted.set_frames [Raw_input_frame.empty];
  (* World with no Audio_command_buffer registered — should not raise *)
  let world    = World.create () in
  let pipeline = Pipeline.Default.create () in
  let progress = My_progress.create ~mode:My_progress.Variable pipeline in
  let _world, _, _ =
    My_loop.step ~progress ~world ~last_time:0.0 ~now:0.016
      ~should_continue:(fun _ -> false)
  in
  Alcotest.(check pass) "no buffer in world is safe" () ()

(* ------------------------------------------------------------------ *)
(* Suite                                                               *)
(* ------------------------------------------------------------------ *)

let tests = [
  "Audio_command_buffer — new buffer is empty",        `Quick, test_create_empty;
  "Audio_command_buffer — add preserves order",        `Quick, test_add_preserves_order;
  "Audio_command_buffer — clear empties buffer",       `Quick, test_clear_empties_buffer;
  "Audio_backend.Null — init is noop",                 `Quick, test_null_init_is_noop;
  "Audio_backend.Null — submit is noop",               `Quick, test_null_submit_is_noop;
  "Audio_backend.Null — shutdown is noop",             `Quick, test_null_shutdown_is_noop;
  "Loop.step — submits commands to backend",           `Quick, test_loop_submits_commands;
  "Loop.step — clears buffer after submit",            `Quick, test_loop_clears_buffer_after_submit;
  "Loop.step — no buffer in world is safe",            `Quick, test_loop_no_buffer_is_safe;
]

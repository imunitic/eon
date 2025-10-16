open Eon_ecs
open Alcotest

module Single_bus = Eon_ecs__Single_bus
module Double_bus = Eon_ecs__Double_bus
module System = Eon_ecs__System

(* -------------------------------------------------------------------------- *)
(* 🧩 Helpers *)
(* -------------------------------------------------------------------------- *)

let make_world () =
  (* Replace with your actual world constructor if needed *)
  World.create ()

(* Mutable log for verifying handler order *)
let log = ref []

let record tag = log := tag :: !log
let reset_log () = log := []
let get_log () = List.rev !log

(* -------------------------------------------------------------------------- *)
(* 🧩 System under test *)
(* -------------------------------------------------------------------------- *)

module Test_system = System.Make(Single_bus)(Double_bus)(Single_bus)

let system_under_test : (string, string, string) Test_system.t =
  Test_system.make_reactive
    ~register:(fun _ -> record "register")
    ~update:(fun _ dt -> record (Printf.sprintf "update(%.2f)" dt))
    ~on_signal:(fun _ _ -> record "signal")
    ~on_event:(fun _ _ -> record "event")
    ~on_command:(fun _ _ -> record "command")
    ()

(* -------------------------------------------------------------------------- *)
(* 🧩 Base System tests *)
(* -------------------------------------------------------------------------- *)

let test_register_and_update  () =
  reset_log ();
  let world = make_world () in
  system_under_test.core.register world;
  system_under_test.core.update world 0.16;
  (check (list string))
    "register + update were called"
    [ "register"; "update(0.16)" ]
    (get_log ())

let test_signal_handler  () =
  reset_log ();
  let world = make_world () in
  system_under_test.on_signal world "signal";
  (check (list string))
    "signal handler executed"
    [ "signal" ]
    (get_log ())

let test_event_handler  () =
  reset_log ();
  let world = make_world () in
  system_under_test.on_event world "event";
  (check (list string))
    "event handler executed"
    [ "event" ]
    (get_log ())

let test_command_handler () =
  reset_log ();
  let world = make_world () in
  system_under_test.on_command world "command";
  (check (list string))
    "command handler executed"
    [ "command" ]
    (get_log ())

(* -------------------------------------------------------------------------- *)
(* 🧩 attach_handlers Tests *)
(* -------------------------------------------------------------------------- *)

let test_attach_handlers_manual () =
  reset_log ();

  let world = make_world () in
  let signal_bus = Single_bus.create () in
  let event_bus = Double_bus.create () in
  let command_bus = Single_bus.create () in

  let sys =
    Test_system.make_reactive
      ~register:(fun _ -> record "register")
      ~on_signal:(fun _ msg -> record ("signal:" ^ msg))
      ~on_event:(fun _ msg -> record ("event:" ^ msg))
      ~on_command:(fun _ msg -> record ("command:" ^ msg))
      ()
  in

  Test_system.attach_handlers
    ~signals:signal_bus
    ~events:event_bus
    ~commands:command_bus
    world sys;

  (* --- Frame 1 --- *)
  Single_bus.emit signal_bus "sig1";
  Single_bus.emit command_bus "cmd1";
  Double_bus.emit event_bus "evt1";

  (* Process same-frame messages (signal, command) *)
  Single_bus.drain signal_bus;
  Single_bus.drain command_bus;

  (* End of frame: swap/deliver next-frame messages (events) *)
  Double_bus.drain event_bus;
  Double_bus.collect event_bus;

  check (list string) "Handlers executed in order"
    [ "register"; "signal:sig1"; "command:cmd1"; "event:evt1" ]
    (get_log ())

let test_attach_handlers_world_fallback () =
  reset_log ();

  let world = make_world () in
  let signal_bus = Single_bus.create () in
  let event_bus = Double_bus.create () in
  let command_bus = Single_bus.create () in

  (* Register the buses as world services *)
  World.add_service world "Signals" signal_bus;
  World.add_service world "Events" event_bus;
  World.add_service world "Commands" command_bus;

  (* Build a system *)
  let sys =
    Test_system.make_reactive
      ~register:(fun _ -> record "register")
      ~on_signal:(fun _ msg -> record ("signal:" ^ msg))
      ~on_event:(fun _ msg -> record ("event:" ^ msg))
      ~on_command:(fun _ msg -> record ("command:" ^ msg))
      ()
  in

  (* Attach handlers without specifying buses explicitly *)
  Test_system.attach_handlers world sys;

  (* Emit and collect twice to trigger next-frame delivery *)
  Single_bus.emit signal_bus "sig2";
  Double_bus.emit event_bus "evt2";
  Single_bus.emit command_bus "cmd2";

  (* Frame 1 — drain same-frame buses (Signal + Command) *)
  Single_bus.collect signal_bus;
  Single_bus.collect command_bus;
  Double_bus.collect event_bus;  (* Does nothing yet *)

  (* Frame 2 — now event_bus current queue has evt1 *)
  Double_bus.drain event_bus;
  Double_bus.collect event_bus;
  
  check (list string) "Handlers executed in order"
    [ "register"; "signal:sig2"; "command:cmd2"; "event:evt2" ]
    (get_log ())

(* -------------------------------------------------------------------------- *)
(* 🧩 Export test list *)
(* -------------------------------------------------------------------------- *)

let tests =
  [
    test_case "register and update" `Quick test_register_and_update;
    test_case "signal handler" `Quick test_signal_handler;
    test_case "event handler" `Quick test_event_handler;
    test_case "command handler" `Quick test_command_handler;
    test_case "attach_handlers manual" `Quick test_attach_handlers_manual;
    test_case "attach_handlers world fallback" `Quick test_attach_handlers_world_fallback;
  ]

open Eon_ecs
open Alcotest

module Single_bus = Eon_ecs__Single_bus
module Double_bus = Eon_ecs__Double_bus
module System = Eon_ecs__System

(* -------------------------------------------------------------------------- *)
(* 🧩 Helpers *)
(* -------------------------------------------------------------------------- *)

let make_world () =
  World.create ()

let log = ref []

let record tag = log := tag :: !log
let reset_log () = log := []
let get_log () = List.rev !log

(* -------------------------------------------------------------------------- *)
(* 🧩 System under test *)
(* -------------------------------------------------------------------------- *)

module Test_system = System.Make(Single_bus)(Double_bus)(Single_bus)

let system_under_test : (string, string, string) Test_system.t =
  Test_system.make
    ~register:(fun _ -> record "register")
    ~update:(fun _ dt -> record (Printf.sprintf "update(%.2f)" dt))
    ~on_signal:(fun _ _ -> record "signal")
    ~on_event:(fun _ _ -> record "event")
    ~on_command:(fun _ _ -> record "command")
    ()

(* -------------------------------------------------------------------------- *)
(* 🧩 Base System tests *)
(* -------------------------------------------------------------------------- *)

let test_register_and_update () =
  reset_log ();
  let world = make_world () in
  Test_system.register system_under_test world;
  Test_system.run system_under_test world 0.16;
  (check (list string))
    "register + update were called"
    [ "register"; "update(0.16)" ]
    (get_log ())

let test_signal_handler () =
  reset_log ();
  let world = make_world () in
  let bus = Single_bus.create () in
  Test_system.attach system_under_test world
    ~signals:bus ~events:(Double_bus.create ()) ~commands:(Single_bus.create ());
  Single_bus.emit bus "signal";
  Single_bus.drain bus;
  (check (list string)) "signal handler executed" [ "signal" ] (get_log ())

let test_event_handler () =
  reset_log ();
  let world = make_world () in
  let bus = Double_bus.create () in
  Test_system.attach system_under_test world
    ~signals:(Single_bus.create ()) ~events:bus ~commands:(Single_bus.create ());
  Double_bus.emit bus "event";
  Double_bus.drain bus;   (* swap: next → current *)
  Double_bus.drain bus;   (* collect current: delivers to subscriber *)
  (check (list string)) "event handler executed" [ "event" ] (get_log ())

let test_command_handler () =
  reset_log ();
  let world = make_world () in
  let bus = Single_bus.create () in
  Test_system.attach system_under_test world
    ~signals:(Single_bus.create ()) ~events:(Double_bus.create ()) ~commands:bus;
  Single_bus.emit bus "command";
  Single_bus.drain bus;
  (check (list string)) "command handler executed" [ "command" ] (get_log ())

(* -------------------------------------------------------------------------- *)
(* 🧩 attach Tests *)
(* -------------------------------------------------------------------------- *)

let test_attach () =
  reset_log ();

  let world = make_world () in
  let signal_bus  = Single_bus.create () in
  let event_bus   = Double_bus.create () in
  let command_bus = Single_bus.create () in

  Test_system.make
    ~register:(fun _ -> record "register")
    ~on_signal:(fun _ msg -> record ("signal:" ^ msg))
    ~on_event:(fun _ msg -> record ("event:" ^ msg))
    ~on_command:(fun _ msg -> record ("command:" ^ msg))
    ()
  |> (fun sys ->
    Test_system.attach sys world
      ~signals:signal_bus
      ~events:event_bus
      ~commands:command_bus);

  Single_bus.emit signal_bus "sig1";
  Single_bus.emit command_bus "cmd1";
  Double_bus.emit event_bus "evt1";

  Single_bus.drain signal_bus;
  Single_bus.drain command_bus;

  Double_bus.drain event_bus;
  Double_bus.collect event_bus;

  check (list string) "Handlers executed in order"
    ["signal:sig1"; "command:cmd1"; "event:evt1" ]
    (get_log ())

(* -------------------------------------------------------------------------- *)
(* 🧩 Export test list *)
(* -------------------------------------------------------------------------- *)

let tests =
  [
    test_case "register and update"  `Quick test_register_and_update;
    test_case "signal handler"       `Quick test_signal_handler;
    test_case "event handler"        `Quick test_event_handler;
    test_case "command handler"      `Quick test_command_handler;
    test_case "attach"               `Quick test_attach;
  ]

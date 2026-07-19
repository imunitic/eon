open Alcotest

module Buses = Eon_ecs__Buses
module Single_bus = Eon_ecs__Single_bus
module Double_bus = Eon_ecs__Double_bus

let test_signals_singleton_identity () =
  (* [Buses.Default.signals ()] is a polymorphic singleton: every call within
     one [Make] instantiation returns a handle to the same physical bus, just
     [Obj.magic]-cast to whatever ['a] the caller asks for. Subscribing via
     one call's handle and emitting via a second call's handle must still
     deliver — that's the identity, not just structural equality. *)
  let received = ref [] in
  let sub_handle : string Single_bus.t = Buses.Default.signals () in
  Single_bus.on sub_handle (fun msg -> received := msg :: !received);
  let emit_handle : string Single_bus.t = Buses.Default.signals () in
  Single_bus.emit emit_handle "hello";
  Single_bus.drain emit_handle;
  check (list string) "delivered through a different call to signals ()" [ "hello" ] !received;
  Buses.Default.unsubscribe_all ()

let test_events_singleton_identity () =
  let received = ref [] in
  let sub_handle : string Double_bus.t = Buses.Default.events () in
  Double_bus.on sub_handle (fun msg -> received := msg :: !received);
  let emit_handle : string Double_bus.t = Buses.Default.events () in
  Double_bus.emit emit_handle "world";
  (* Double_bus is next-frame: needs a drain to make it visible. *)
  Double_bus.drain emit_handle;
  Double_bus.collect sub_handle;
  check (list string) "delivered through a different call to events ()" [ "world" ] !received;
  Buses.Default.unsubscribe_all ()

let test_commands_singleton_identity () =
  let received = ref [] in
  let sub_handle : int Single_bus.t = Buses.Default.commands () in
  Single_bus.on sub_handle (fun msg -> received := msg :: !received);
  let emit_handle : int Single_bus.t = Buses.Default.commands () in
  Single_bus.emit emit_handle 7;
  Single_bus.drain emit_handle;
  check (list int) "delivered through a different call to commands ()" [ 7 ] !received;
  Buses.Default.unsubscribe_all ()

let test_unsubscribe_all_clears_every_bus () =
  let signals_fired = ref false in
  let events_fired = ref false in
  let commands_fired = ref false in
  let signals : unit Single_bus.t = Buses.Default.signals () in
  let events : unit Double_bus.t = Buses.Default.events () in
  let commands : unit Single_bus.t = Buses.Default.commands () in
  Single_bus.on signals (fun () -> signals_fired := true);
  Double_bus.on events (fun () -> events_fired := true);
  Single_bus.on commands (fun () -> commands_fired := true);

  Buses.Default.unsubscribe_all ();

  Single_bus.emit signals ();
  Single_bus.drain signals;
  Double_bus.emit events ();
  Double_bus.drain events;
  Double_bus.collect events;
  Single_bus.emit commands ();
  Single_bus.drain commands;

  check bool "signals subscriber removed" false !signals_fired;
  check bool "events subscriber removed" false !events_fired;
  check bool "commands subscriber removed" false !commands_fired

let test_separate_instantiations_are_isolated () =
  let module Buses_a = Buses.Make (Single_bus) (Double_bus) (Single_bus) in
  let module Buses_b = Buses.Make (Single_bus) (Double_bus) (Single_bus) in
  let a_received = ref [] in
  let b_received = ref [] in
  let a_signals : string Single_bus.t = Buses_a.signals () in
  let b_signals : string Single_bus.t = Buses_b.signals () in
  Single_bus.on a_signals (fun msg -> a_received := msg :: !a_received);
  Single_bus.on b_signals (fun msg -> b_received := msg :: !b_received);

  Single_bus.emit a_signals "only-a";
  Single_bus.drain a_signals;

  check (list string) "instantiation A received its own message" [ "only-a" ] !a_received;
  check (list string) "instantiation B is untouched by A's traffic" [] !b_received

let tests =
  [
    test_case "signals () is a singleton across calls" `Quick test_signals_singleton_identity;
    test_case "events () is a singleton across calls" `Quick test_events_singleton_identity;
    test_case "commands () is a singleton across calls" `Quick test_commands_singleton_identity;
    test_case "unsubscribe_all clears signals, events, and commands" `Quick
      test_unsubscribe_all_clears_every_bus;
    test_case "two Make instantiations don't share state" `Quick
      test_separate_instantiations_are_isolated;
  ]

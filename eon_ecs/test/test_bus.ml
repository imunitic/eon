open Alcotest

module Single_bus = Eon_ecs__Single_bus
module Double_bus = Eon_ecs__Double_bus


let make_collector () =
  let acc = ref [] in
  (acc, fun msg -> acc := msg :: !acc)


let test_single_bus_basic () =
  let bus = Single_bus.create () in
  let (acc, handler) = make_collector () in
  Single_bus.on bus handler;
  Single_bus.emit bus "hello";
  Single_bus.emit bus "world";
  Single_bus.collect bus;
  check (list string) "messages match" ["world"; "hello"] !acc

let test_single_bus_empty_collect () =
  let bus = Single_bus.create () in
  (* Should not raise or do anything *)
  Single_bus.collect bus

let test_single_bus_order () =
  let bus = Single_bus.create () in
  let acc = ref [] in
  Single_bus.on bus (fun m -> acc := !acc @ [m]);
  List.iter (Single_bus.emit bus) [1; 2; 3];
  Single_bus.collect bus;
  check (list int) "order preserved" [1; 2; 3] !acc


let test_double_bus_basic () =
  let bus = Double_bus.create () in
  let (acc, handler) = make_collector () in
  Double_bus.on bus handler;

  (* Emit in frame 1 — should NOT be processed yet *)
  Double_bus.emit bus "hello";
  Double_bus.collect bus;
  check (list string) "no messages yet" [] !acc;

  (* Drain (swap buffers) — now "hello" moves to current queue *)
  Double_bus.drain bus;
  Double_bus.collect bus;
  check (list string) "message processed next frame" ["hello"] !acc

let test_double_bus_multiple_frames () =
  let bus = Double_bus.create () in
  let acc = ref [] in
  Double_bus.on bus (fun m -> acc := !acc @ [m]);

  Double_bus.emit bus "A";
  Double_bus.drain bus;  (* Frame 1 -> 2 *)
  Double_bus.collect bus;
  Double_bus.emit bus "B";
  Double_bus.drain bus;  (* Frame 2 -> 3 *)
  Double_bus.collect bus;

  check (list string) "messages processed in order" ["A"; "B"] !acc


let tests =
  [
    test_case "Single_bus basic delivery"    `Quick test_single_bus_basic;
    test_case "Single_bus empty collect"     `Quick test_single_bus_empty_collect;
    test_case "Single_bus message order"     `Quick test_single_bus_order;
    test_case "Double_bus next-frame"        `Quick test_double_bus_basic;
    test_case "Double_bus multi-frame order" `Quick test_double_bus_multiple_frames;
  ]

open Eon_engine

(* Simple command type for tests — no need to use Render_commands.command *)
type cmd = A | B | C | D

(* ------------------------------------------------------------------ *)
(* Render_stream unit tests                                            *)
(* ------------------------------------------------------------------ *)

let test_create_is_empty () =
  let s = Render_stream.create () in
  let world_cmds  = ref [] in
  let screen_cmds = ref [] in
  Render_stream.iter_world  s (fun c -> world_cmds  := c :: !world_cmds);
  Render_stream.iter_screen s (fun c -> screen_cmds := c :: !screen_cmds);
  Alcotest.(check int) "world empty on create"  0 (List.length !world_cmds);
  Alcotest.(check int) "screen empty on create" 0 (List.length !screen_cmds)

let test_world_emission_order () =
  let s = Render_stream.create () in
  Render_stream.add_world s A;
  Render_stream.add_world s B;
  Render_stream.add_world s C;
  let acc = ref [] in
  Render_stream.iter_world s (fun c -> acc := c :: !acc);
  Alcotest.(check (list (Alcotest.testable (fun ppf c -> Format.pp_print_string ppf (match c with A -> "A" | B -> "B" | C -> "C" | D -> "D")) (=))))
    "world commands in emission order" [A; B; C] (List.rev !acc)

let test_screen_emission_order () =
  let s = Render_stream.create () in
  Render_stream.add_screen s B;
  Render_stream.add_screen s D;
  let acc = ref [] in
  Render_stream.iter_screen s (fun c -> acc := c :: !acc);
  Alcotest.(check (list (Alcotest.testable (fun ppf c -> Format.pp_print_string ppf (match c with A -> "A" | B -> "B" | C -> "C" | D -> "D")) (=))))
    "screen commands in emission order" [B; D] (List.rev !acc)

let test_world_and_screen_are_independent () =
  let s = Render_stream.create () in
  Render_stream.add_world  s A;
  Render_stream.add_screen s B;
  Render_stream.add_world  s C;
  let world  = ref [] in
  let screen = ref [] in
  Render_stream.iter_world  s (fun c -> world  := c :: !world);
  Render_stream.iter_screen s (fun c -> screen := c :: !screen);
  Alcotest.(check int) "world has 2"  2 (List.length !world);
  Alcotest.(check int) "screen has 1" 1 (List.length !screen)

let test_clear_resets_both_lists () =
  let s = Render_stream.create () in
  Render_stream.add_world  s A;
  Render_stream.add_screen s B;
  Render_stream.clear s;
  let world  = ref [] in
  let screen = ref [] in
  Render_stream.iter_world  s (fun c -> world  := c :: !world);
  Render_stream.iter_screen s (fun c -> screen := c :: !screen);
  Alcotest.(check int) "world empty after clear"  0 (List.length !world);
  Alcotest.(check int) "screen empty after clear" 0 (List.length !screen)

let test_clear_then_refill () =
  let s = Render_stream.create () in
  Render_stream.add_world s A;
  Render_stream.add_world s B;
  Render_stream.clear s;
  Render_stream.add_world s C;
  Render_stream.add_world s D;
  let acc = ref [] in
  Render_stream.iter_world s (fun c -> acc := c :: !acc);
  Alcotest.(check int) "two commands after refill" 2 (List.length !acc)

(* ------------------------------------------------------------------ *)
(* Render_stream_collector unit tests                                  *)
(* ------------------------------------------------------------------ *)

let world_rw = World.create ()
let world    = World.readonly world_rw

let test_collector_empty_collect () =
  let c = Render_stream_collector.create () in
  let s = Render_stream.create () in
  Render_stream_collector.collect c (world) s;
  let acc = ref [] in
  Render_stream.iter_world s (fun cmd -> acc := cmd :: !acc);
  Alcotest.(check int) "no commands emitted" 0 (List.length !acc)

let test_collector_single_phase () =
  let c = Render_stream_collector.create () in
  let c = Render_stream_collector.add_phase `Draw c in
  let c = Render_stream_collector.add_collector `Draw
    (fun _w s -> Render_stream.add_world s A) c in
  let s = Render_stream.create () in
  Render_stream_collector.collect c (world) s;
  let acc = ref [] in
  Render_stream.iter_world s (fun cmd -> acc := cmd :: !acc);
  Alcotest.(check int) "one command emitted" 1 (List.length !acc)

let test_collector_phase_order () =
  (* Camera phase must run before Draw phase — Set_camera should come first *)
  let order = ref [] in
  let c = Render_stream_collector.create () in
  let c = Render_stream_collector.add_phase `Camera c in
  let c = Render_stream_collector.add_phase `Draw ~after:`Camera c in
  let c = Render_stream_collector.add_collector `Camera
    (fun _w _s -> order := `Camera :: !order) c in
  let c = Render_stream_collector.add_collector `Draw
    (fun _w _s -> order := `Draw :: !order) c in
  let s = Render_stream.create () in
  Render_stream_collector.collect c (world) s;
  Alcotest.(check (list (Alcotest.testable
    (fun ppf p -> Format.pp_print_string ppf (match p with `Camera -> "Camera" | `Draw -> "Draw"))
    (=))))
    "Camera before Draw" [`Camera; `Draw] (List.rev !order)

let test_collector_multiple_collectors_in_phase () =
  let acc = ref [] in
  let c = Render_stream_collector.create () in
  let c = Render_stream_collector.add_phase `Draw c in
  let c = Render_stream_collector.add_collector `Draw
    (fun _w _s -> acc := 1 :: !acc) c in
  let c = Render_stream_collector.add_collector `Draw
    (fun _w _s -> acc := 2 :: !acc) c in
  let c = Render_stream_collector.add_collector `Draw
    (fun _w _s -> acc := 3 :: !acc) c in
  let s = Render_stream.create () in
  Render_stream_collector.collect c (world) s;
  Alcotest.(check (list int))
    "collectors run in addition order" [1; 2; 3] (List.rev !acc)

let test_collector_unknown_after_raises () =
  let c = Render_stream_collector.create () in
  Alcotest.check_raises
    "unknown ~after raises Invalid_argument"
    (Invalid_argument "Render_stream_collector.add_phase: ~after phase not registered")
    (fun () ->
       ignore (Render_stream_collector.add_phase `Draw ~after:`Unknown c))

let test_collector_unknown_phase_raises () =
  let c = Render_stream_collector.create () in
  Alcotest.check_raises
    "add_collector with unregistered phase raises Invalid_argument"
    (Invalid_argument "Render_stream_collector.add_collector: phase not registered")
    (fun () ->
       ignore (Render_stream_collector.add_collector `Ghost
         (fun _w _s -> ()) c))

(* ------------------------------------------------------------------ *)
(* Test list                                                           *)
(* ------------------------------------------------------------------ *)

let tests = [
  "create is empty",             `Quick, test_create_is_empty;
  "world emission order",        `Quick, test_world_emission_order;
  "screen emission order",       `Quick, test_screen_emission_order;
  "world and screen independent",`Quick, test_world_and_screen_are_independent;
  "clear resets both lists",     `Quick, test_clear_resets_both_lists;
  "clear then refill",           `Quick, test_clear_then_refill;
  "collector empty collect",     `Quick, test_collector_empty_collect;
  "collector single phase",      `Quick, test_collector_single_phase;
  "collector phase order",       `Quick, test_collector_phase_order;
  "multiple collectors in phase",`Quick, test_collector_multiple_collectors_in_phase;
  "unknown ~after raises",       `Quick, test_collector_unknown_after_raises;
  "unknown phase raises",        `Quick, test_collector_unknown_phase_raises;
]

open Eon_engine

(* ------------------------------------------------------------------ *)
(* store / fetch                                                        *)
(* ------------------------------------------------------------------ *)

let test_store_fetch_roundtrip () =
  let world = World.create () in
  Time.store world { Time.delta = 0.016; elapsed = 1.0; frame = 60 };
  let t = Time.fetch world in
  Alcotest.(check (float 1e-9)) "delta"   0.016 t.Time.delta;
  Alcotest.(check (float 1e-9)) "elapsed" 1.0   t.Time.elapsed;
  Alcotest.(check int)          "frame"   60    t.Time.frame

let test_fetch_raises_if_absent () =
  let world = World.create () in
  Alcotest.check_raises "Not_found if absent" Not_found
    (fun () -> ignore (Time.fetch world))

let test_store_overwrites () =
  let world = World.create () in
  Time.store world Time.zero;
  Time.store world { Time.delta = 0.1; elapsed = 0.1; frame = 1 };
  let t = Time.fetch world in
  Alcotest.(check (float 1e-9)) "overwritten elapsed" 0.1 t.Time.elapsed

let test_ro_world_can_fetch () =
  let world = World.create () in
  Time.store world Time.zero;
  let ro = World.readonly world in
  let t = Time.fetch ro in
  Alcotest.(check int) "ro fetch frame" 0 t.Time.frame

(* ------------------------------------------------------------------ *)
(* zero                                                                 *)
(* ------------------------------------------------------------------ *)

let test_zero_values () =
  Alcotest.(check (float 1e-9)) "zero.delta"   0. Time.zero.Time.delta;
  Alcotest.(check (float 1e-9)) "zero.elapsed" 0. Time.zero.Time.elapsed;
  Alcotest.(check int)          "zero.frame"   0  Time.zero.Time.frame

(* ------------------------------------------------------------------ *)
(* write — accumulates correctly                                        *)
(* ------------------------------------------------------------------ *)

let test_write_first_frame_no_prior_store () =
  let world = World.create () in
  Time.write world 0.016;
  let t = Time.fetch world in
  Alcotest.(check (float 1e-9)) "delta"   0.016 t.Time.delta;
  Alcotest.(check (float 1e-9)) "elapsed" 0.016 t.Time.elapsed;
  Alcotest.(check int)          "frame"   1     t.Time.frame

let test_write_accumulates_elapsed () =
  let world = World.create () in
  Time.store world Time.zero;
  Time.write world 0.016;
  Time.write world 0.016;
  Time.write world 0.016;
  let t = Time.fetch world in
  Alcotest.(check (float 1e-9)) "elapsed after 3 frames" 0.048 t.Time.elapsed;
  Alcotest.(check int)          "frame after 3 writes"   3     t.Time.frame

let test_write_delta_is_current_dt () =
  let world = World.create () in
  Time.store world Time.zero;
  Time.write world 0.033;
  let t = Time.fetch world in
  Alcotest.(check (float 1e-9)) "delta reflects current dt" 0.033 t.Time.delta

let test_write_zero_dt_does_not_advance () =
  let world = World.create () in
  Time.store world Time.zero;
  Time.write world 0.016;
  Time.write world 0.0;
  let t = Time.fetch world in
  Alcotest.(check (float 1e-9)) "elapsed unchanged on dt=0" 0.016 t.Time.elapsed;
  Alcotest.(check int)          "frame still advances"      2     t.Time.frame

(* ------------------------------------------------------------------ *)
(* Suite                                                               *)
(* ------------------------------------------------------------------ *)

let tests = [
  "Time — store/fetch round-trip",              `Quick, test_store_fetch_roundtrip;
  "Time — fetch raises if absent",              `Quick, test_fetch_raises_if_absent;
  "Time — store overwrites",                    `Quick, test_store_overwrites;
  "Time — ro world can fetch",                  `Quick, test_ro_world_can_fetch;
  "Time — zero has correct values",             `Quick, test_zero_values;
  "Time — write on first frame (no prior store)", `Quick, test_write_first_frame_no_prior_store;
  "Time — write accumulates elapsed",           `Quick, test_write_accumulates_elapsed;
  "Time — write delta reflects current dt",     `Quick, test_write_delta_is_current_dt;
  "Time — write with dt=0 does not advance elapsed", `Quick, test_write_zero_dt_does_not_advance;
]

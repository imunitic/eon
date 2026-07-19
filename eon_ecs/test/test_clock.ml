open Alcotest

module Clock = Eon_ecs__Clock

let test_now_returns_a_float () =
  let t = Clock.Mtime.now () in
  check bool "now () : float" true (Float.is_finite t)

let test_now_is_monotonic () =
  let t0 = Clock.Mtime.now () in
  (* A tiny busy-loop between samples, so the assertion below isn't
     trivially true from a single instruction's worth of clock
     granularity — real elapsed time, not just two back-to-back calls. *)
  let acc = ref 0 in
  for i = 1 to 200_000 do
    acc := !acc + i
  done;
  ignore !acc;
  let t1 = Clock.Mtime.now () in
  check bool "a later sample is never earlier than an earlier one" true (t1 >= t0)

let tests =
  [
    test_case "now () returns a float" `Quick test_now_returns_a_float;
    test_case "now () never decreases between calls" `Quick test_now_is_monotonic;
  ]

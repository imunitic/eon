open Alcotest
module Entity_id = Eon_ecs__Entity_id

(* 1. Create and access parts *)
let test_make_and_access () =
  let id = Entity_id.make 42 3 in
  check int "index part" 42 (Entity_id.index id);
  check int "generation part" 3 (Entity_id.generation id)

(* 2. Equality checks *)
let test_equality () =
  let a = Entity_id.make 10 1 in
  let b = Entity_id.make 10 1 in
  let c = Entity_id.make 10 2 in
  check bool "equal IDs" true (Entity_id.equal a b);
  check bool "different generations" false (Entity_id.equal a c)

(* 3. Invalid sentinel *)
let test_invalid_id () =
  let invalid = Entity_id.invalid in
  check bool "invalid should not equal valid" false
    (Entity_id.equal invalid (Entity_id.make 0 0));
  check int "invalid index is -1" (-1) (Entity_id.index invalid)

(* 4. Determinism *)
let test_determinism () =
  let a1 = Entity_id.make 7 2 in
  let a2 = Entity_id.make 7 2 in
  check bool "make is deterministic" true (Entity_id.equal a1 a2)

let tests = [
  test_case "make and access" `Quick test_make_and_access;
  test_case "equality" `Quick test_equality;
  test_case "invalid sentinel" `Quick test_invalid_id;
  test_case "determinism" `Quick test_determinism;
]

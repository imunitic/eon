open Alcotest

module Sparse_set = Eon_ecs__Sparse_set
module Entity_id  = Eon_ecs__Entity_id


let e idx = Entity_id.make idx 0


let test_create_empty () =
  let set = Sparse_set.create ~capacity:4 () in
  check int "initial size" 0 (Sparse_set.size set);
  check int "initial capacity" 4 (Sparse_set.capacity set)

let test_add_get () =
  let set = Sparse_set.create ~capacity:2 () in
  let ent = e 1 in
  Sparse_set.add set ent 42;
  check (option int) "get existing" (Some 42) (Sparse_set.get set ent);
  check int "size after add" 1 (Sparse_set.size set)

let test_contains () =
  let set = Sparse_set.create ~capacity:2 () in
  let ent = e 0 in
  Sparse_set.add set ent 100;
  check bool "contains true" true (Sparse_set.contains set ent);
  check bool "contains false" false (Sparse_set.contains set (e 1))

let test_remove () =
  let set = Sparse_set.create ~capacity:2 () in
  let ent = e 0 in
  Sparse_set.add set ent 5;
  Sparse_set.remove set ent;
  check (option int) "removed value" None (Sparse_set.get set ent);
  check bool "no longer contains" false (Sparse_set.contains set ent)

let test_swap_remove_correctness () =
  (* Ensures the swap-remove maintains valid dense/sparse mapping *)
  let set = Sparse_set.create ~capacity:4 () in
  let e1, e2 = e 0, e 1 in
  Sparse_set.add set e1 "foo";
  Sparse_set.add set e2 "bar";
  Sparse_set.remove set e1;
  (* After removing e1, e2 should still exist and be retrievable *)
  check (option string) "other value remains" (Some "bar") (Sparse_set.get set e2);
  check int "size after remove" 1 (Sparse_set.size set)

let test_grow () =
  let set = Sparse_set.create ~capacity:1 () in
  Sparse_set.add set (e 0) 1;
  Sparse_set.add set (e 1) 2;  (* triggers grow *)
  check bool "contains after grow" true (Sparse_set.contains set (e 1));
  check int "size after grow" 2 (Sparse_set.size set)

let test_iter () =
  let set = Sparse_set.create ~capacity:3 () in
  let e1, e2 = e 0, e 1 in
  Sparse_set.add set e1 "a";
  Sparse_set.add set e2 "b";
  let acc = ref [] in
  Sparse_set.iter (fun idx v -> acc := (idx, v) :: !acc) set;
  let found = List.map snd !acc |> List.sort compare in
  check (list string) "iter returns both" ["a"; "b"] found

let test_set_value () =
  let set = Sparse_set.create ~capacity:2 () in
  let ent = e 0 in
  (* set_value should add when missing *)
  Sparse_set.set_value set ent 10;
  check int "size after set insert" 1 (Sparse_set.size set);
  check (option int) "value after insert" (Some 10) (Sparse_set.get set ent);

  (* and overwrite when present without changing size *)
  Sparse_set.set_value set ent 42;
  check int "size unchanged" 1 (Sparse_set.size set);
  check (option int) "overwritten value" (Some 42) (Sparse_set.get set ent)


let tests =
  [
    test_case "create empty" `Quick test_create_empty;
    test_case "add/get" `Quick test_add_get;
    test_case "contains" `Quick test_contains;
    test_case "remove" `Quick test_remove;
    test_case "swap remove correctness" `Quick test_swap_remove_correctness;
    test_case "grow" `Quick test_grow;
    test_case "iter" `Quick test_iter;
    test_case "set_value" `Quick test_set_value;
  ]

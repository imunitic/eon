open Alcotest
open Eon_ecs

(* Test helpers *)

let check_alive world e expected =
  check bool "is_alive" expected (World.is_alive world e)

(* ------- Tests ------- *)

let test_create_entity () = 
  let world = World.create () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  check int "first entity index" 0 (Entity_id.index e1);
  check int "second entity index" 1 (Entity_id.index e2);
  check_alive world e1 true;
  check_alive world e2 true

let test_destroy_entity () =
  let world = World.create () in
  let e1 = World.create_entity world in
  World.destroy_entity world e1;
  check_alive world e1 false

let test_reuse_index () =
  let world = World.create () in
  let e1 = World.create_entity world in
  World.destroy_entity world e1;
  let e2 = World.create_entity world in
  check int "index reused" (Entity_id.index e1) (Entity_id.index e2);
  check bool "generation incremented" ((Entity_id.generation e2) > (Entity_id.generation e1)) true;
  check_alive world e1 false;
  check_alive world e2 true

let test_multiple_entities () =
  let world = World.create () in
  let es = List.init 10 (fun _ -> World.create_entity world) in
  check int "count" (List.length es) (World.count_entities world);
  List.iter (fun e -> check_alive world e true) es;
  List.iter (World.destroy_entity world) es;
  List.iter (fun e -> check_alive world e false) es

(* ------- Test runner ------- *)
let tests =
  [
    test_case "create entity" `Quick test_create_entity;
    test_case "destroy entity" `Quick test_destroy_entity;
    test_case "reuse index" `Quick test_reuse_index;
    test_case "multiple entities" `Quick test_multiple_entities;
  ]

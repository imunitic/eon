open Alcotest

module Query = Eon_ecs__Query
module World = Eon_ecs__World
module Entity_id = Eon_ecs__Entity_id

let float_eq a b = abs_float (a -. b) < 0.0001

(* ------------------------------------------------------------- *)
(* iter1 — single component                                      *)
(* ------------------------------------------------------------- *)
let test_iter1 () =
  let world = World.create () in
  World.register_component world ~name:"Position" ~id:0 |> ignore;

  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let e3 = World.create_entity world in

  World.add_component world e1 ~name:"Position" (10.0, 20.0);
  World.add_component world e2 ~name:"Position" (30.0, 40.0);
  World.add_component world e3 ~name:"Position" (40.0, 50.0);

  let results = ref [] in
  Query.iter1 world "Position" (fun eid (x, y) ->
      results := (Entity_id.index eid, x, y) :: !results);

  check int "iter1 count" 3 (List.length !results)

(* ------------------------------------------------------------- *)
(* iter2 — two-component intersection                            *)
(* ------------------------------------------------------------- *)
let test_iter2 () =
  let world = World.create () in
  World.register_component world ~name:"Position" ~id:0 |> ignore;
  World.register_component world ~name:"Velocity" ~id:1 |> ignore;

  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let e3 = World.create_entity world in

  (* e1 has both Position and Velocity *)
  World.add_component world e1 ~name:"Position" (1.0, 2.0);
  World.add_component world e1 ~name:"Velocity" (0.5, 0.5);

  (* e2 has only Position *)
  World.add_component world e2 ~name:"Position" (10.0, 20.0);

  (* e3 has only Velocity *)
  World.add_component world e3 ~name:"Velocity" (3.0, 4.0);

  let results = ref [] in
  Query.iter2 world "Position" "Velocity" (fun eid (x, y) (vx, vy) ->
      results := (Entity_id.index eid, x +. y +. vx +. vy) :: !results);

  check int "iter2 shared entity count" 1 (List.length !results);
  match !results with
  | [ (_, sum) ] -> check bool "sum correct" true (float_eq sum 4.0)
  | _ -> fail "Unexpected results in iter2"

(* ------------------------------------------------------------- *)
(* iter2 — argument order when c2 set is smaller than c1        *)
(* Regression test for the base-set swap bug: when s2.size <=   *)
(* s1.size the wrong set is chosen as the iteration base,        *)
(* causing c1 and c2 values to be passed to f in swapped order. *)
(* ------------------------------------------------------------- *)
let test_iter2_arg_order () =
  let world = World.create () in
  World.register_component world ~name:"Position" ~id:0 |> ignore;
  World.register_component world ~name:"Velocity" ~id:1 |> ignore;

  (* Two entities carry Position — s1.size = 2 *)
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 ~name:"Position" (10.0, 20.0);
  World.add_component world e2 ~name:"Position" (99.0, 99.0);

  (* Only e1 carries Velocity — s2.size = 1, so s2 becomes the
     iteration base and the bug causes c2's value to land in v1. *)
  World.add_component world e1 ~name:"Velocity" (1.0, 2.0);

  let got_pos = ref (0.0, 0.0) in
  let got_vel = ref (0.0, 0.0) in
  Query.iter2 world "Position" "Velocity"
    (fun _ pos vel ->
       got_pos := pos;
       got_vel := vel);

  check bool "position x is 10" true (float_eq (fst !got_pos) 10.0);
  check bool "position y is 20" true (float_eq (snd !got_pos) 20.0);
  check bool "velocity x is 1"  true (float_eq (fst !got_vel)  1.0);
  check bool "velocity y is 2"  true (float_eq (snd !got_vel)  2.0)

(* ------------------------------------------------------------- *)
(* count — shared component count                                *)
(* ------------------------------------------------------------- *)
let test_count () =
  let world = World.create () in
  World.register_component world ~name:"Health" ~id:0 |> ignore;
  World.register_component world ~name:"Mana" ~id:1 |> ignore;

  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let e3 = World.create_entity world in

  World.add_component world e1 ~name:"Health" 100;
  World.add_component world e1 ~name:"Mana" 50;

  World.add_component world e2 ~name:"Health" 80;
  World.add_component world e3 ~name:"Mana" 10;

  let cnt = Query.count world [ "Health"; "Mana" ] in
  check int "count shared entities" 1 cnt

(* ------------------------------------------------------------- *)
(* iter3 + iter4 — higher arity queries                          *)
(* ------------------------------------------------------------- *)
let test_iter3_iter4 () =
  let world = World.create () in
  World.register_component world ~name:"A" ~id:0 |> ignore;
  World.register_component world ~name:"B" ~id:1 |> ignore;
  World.register_component world ~name:"C" ~id:2 |> ignore;
  World.register_component world ~name:"D" ~id:3 |> ignore;

  let e = World.create_entity world in
  World.add_component world e ~name:"A" 1;
  World.add_component world e ~name:"B" 2;
  World.add_component world e ~name:"C" 3;
  World.add_component world e ~name:"D" 4;

  let sum3 = ref 0 in
  Query.iter3 world "A" "B" "C" (fun _ a b c ->
      sum3 := !sum3 + a + b + c);

  let sum4 = ref 0 in
  Query.iter4 world "A" "B" "C" "D" (fun _ a b c d ->
      sum4 := !sum4 + a + b + c + d);

  check int "iter3 sum" 6 !sum3;
  check int "iter4 sum" 10 !sum4

(* ------------------------------------------------------------- *)
(* iter_entities tests                                           *)
(* ------------------------------------------------------------- *)

let test_iter_entities_single () =
  let world = World.create () in
  World.register_component world ~name:"Hp" ~id:0 |> ignore;
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 ~name:"Hp" 100;
  World.add_component world e2 ~name:"Hp" 50;
  let count = ref 0 in
  Query.iter_entities world ["Hp"] (fun _ -> incr count);
  check int "single component visits all holders" 2 !count

let test_iter_entities_intersection () =
  let world = World.create () in
  World.register_component world ~name:"A" ~id:0 |> ignore;
  World.register_component world ~name:"B" ~id:1 |> ignore;
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 ~name:"A" ();
  World.add_component world e1 ~name:"B" ();
  World.add_component world e2 ~name:"A" ();  (* B is absent *)
  let count = ref 0 in
  Query.iter_entities world ["A"; "B"] (fun _ -> incr count);
  check int "two-component intersection yields one entity" 1 !count

let test_iter_entities_empty_list () =
  let world = World.create () in
  let _e = World.create_entity world in
  let count = ref 0 in
  Query.iter_entities world [] (fun _ -> incr count);
  check int "empty name list yields nothing" 0 !count

let test_iter_entities_unregistered_raises () =
  let world = World.create () in
  Alcotest.check_raises
    "unregistered name raises Invalid_argument"
    (Invalid_argument "iter_entities: unregistered component: Foo")
    (fun () -> Query.iter_entities world ["Foo"] (fun _ -> ()))

let test_iter_entities_destroyed_excluded () =
  let world = World.create () in
  World.register_component world ~name:"X" ~id:0 |> ignore;
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 ~name:"X" ();
  World.add_component world e2 ~name:"X" ();
  World.destroy_entity world e1;
  let count = ref 0 in
  Query.iter_entities world ["X"] (fun _ -> incr count);
  check int "destroyed entity not visited" 1 !count

let test_iter_entities_four_components () =
  let world = World.create () in
  World.register_component world ~name:"A" ~id:0 |> ignore;
  World.register_component world ~name:"B" ~id:1 |> ignore;
  World.register_component world ~name:"C" ~id:2 |> ignore;
  World.register_component world ~name:"D" ~id:3 |> ignore;
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 ~name:"A" ();
  World.add_component world e1 ~name:"B" ();
  World.add_component world e1 ~name:"C" ();
  World.add_component world e1 ~name:"D" ();
  World.add_component world e2 ~name:"A" ();
  World.add_component world e2 ~name:"B" ();
  World.add_component world e2 ~name:"C" ();
  (* e2 lacks D *)
  let count = ref 0 in
  Query.iter_entities world ["A"; "B"; "C"; "D"] (fun _ -> incr count);
  check int "four-component intersection" 1 !count

(* ------------------------------------------------------------- *)
(* Suite registration                                             *)
(* ------------------------------------------------------------- *)
let tests =
  [
    test_case "iter1" `Quick test_iter1;
    test_case "iter2" `Quick test_iter2;
    test_case "iter2 argument order" `Quick test_iter2_arg_order;
    test_case "iter3 and iter4" `Quick test_iter3_iter4;
    test_case "count" `Quick test_count;
  ]

let iter_entities_tests =
  [
    test_case "single component" `Quick test_iter_entities_single;
    test_case "intersection" `Quick test_iter_entities_intersection;
    test_case "empty name list" `Quick test_iter_entities_empty_list;
    test_case "unregistered raises" `Quick test_iter_entities_unregistered_raises;
    test_case "destroyed excluded" `Quick test_iter_entities_destroyed_excluded;
    test_case "four components" `Quick test_iter_entities_four_components;
  ]

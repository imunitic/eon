(** Tests for Eon Engine Query module *)

open Eon_ecs

module Query = Eon_engine.Query.Make(Eon_engine.Sparse_set_backend)

(* Define test component types *)
type position = { x : float; y : float }
type velocity = { dx : float; dy : float }
type health = { current : int; max : int }
type frozen = { value : bool }

(** Helper to create a world with registered components *)
let create_world_with_components () =
  let world = World.create () in
  (* Register some test components *)
  ignore (World.register_component world ~name:"Position" ~id:0);
  ignore (World.register_component world ~name:"Velocity" ~id:1);
  ignore (World.register_component world ~name:"Health" ~id:2);
  ignore (World.register_component world ~name:"Frozen" ~id:3);
  world

(** Test basic iter1 functionality *)
let test_iter1 () =
  let world = create_world_with_components () in
  
  (* Create entities with Position component *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  
  (* Create entity without Position *)
  let e3 = World.create_entity world in
  World.add_component world e3 ~name:"Health" { current = 100; max = 100 };
  
  (* Query for entities with Position *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.iter1 (fun entity pos ->
    results := (entity, pos) :: !results
  );
  
  (* Should have 2 results *)
  Alcotest.(check int) "iter1 should find 2 entities" 2 (List.length !results);
  
  (* Verify both entities are in results *)
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e1 should be in results" true (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should be in results" true (List.mem e2 entity_ids);
  Alcotest.(check bool) "e3 should not be in results" false (List.mem e3 entity_ids)

(** Test basic iter2 functionality *)
let test_iter2 () =
  let world = create_world_with_components () in
  
  (* Create entity with both Position and Velocity *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Velocity" { dx = 0.5; dy = 0.5 };
  
  (* Create entity with only Position *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  
  (* Create entity with only Velocity *)
  let e3 = World.create_entity world in
  World.add_component world e3 ~name:"Velocity" { dx = 1.0; dy = 1.0 };
  
  (* Query for entities with both Position and Velocity *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.with_component "Velocity"
  |> Query.iter2 (fun entity pos vel ->
    results := (entity, pos, vel) :: !results
  );
  
  (* Should have 1 result (only e1 has both) *)
  Alcotest.(check int) "iter2 should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e1 *)
  match !results with
  | [(entity, pos, vel)] ->
      Alcotest.(check bool) "result should be e1" true (Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx
  | _ -> Alcotest.fail "Expected exactly 1 result"

(** Test iter2 with having filter *)
let test_iter1_with_having () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Frozen" { value = true };
  
  (* Create entity with Position but not Frozen *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  
  (* Query for entities with Position that also have Frozen *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.having "Frozen"
  |> Query.iter1 (fun entity pos ->
    results := (entity, pos) :: !results
  );
  
  (* Should have 1 result (only e1 has both) *)
  Alcotest.(check int) "iter2 with having should find 1 entity" 1 (List.length !results)

(** Test iter2 with not_having filter *)
let test_iter1_with_not_having () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Frozen" { value = true };
  
  (* Create entity with Position but not Frozen *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  
  (* Query for entities with Position that do not have Frozen *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.not_having "Frozen"
  |> Query.iter1 (fun entity pos ->
    results := (entity, pos) :: !results
  );
  
  (* Should have 1 result (only e2 does not have Frozen) *)
  Alcotest.(check int) "iter2 with not_having should find 1 entity" 1 (List.length !results)

(** Test count functionality *)
let test_count () =
  let world = create_world_with_components () in
  
  (* Create 3 entities with Position *)
  for i = 1 to 3 do
    let e = World.create_entity world in
    World.add_component world e ~name:"Position" { x = float i; y = float i }
  done;
  
  (* Create 1 entity without Position *)
  let e = World.create_entity world in
  World.add_component world e ~name:"Health" { current = 100; max = 100 };
  
  (* Count entities with Position *)
  let count =
    Query.from world
    |> Query.with_component "Position"
    |> Query.count
  in
  
  Alcotest.(check int) "count should return 3" 3 count

(** Test arity mismatch raises error *)
let test_arity_mismatch () =
  let world = create_world_with_components () in
  
  (* Try to use iter2 with only one component *)
  let should_raise () =
    Query.from world
    |> Query.with_component "Position"
    |> Query.iter2 (fun _ _ _ -> ())
  in
  
  Alcotest.(check bool) "iter2 with 1 component should raise" true
    (try should_raise (); false with Invalid_argument _ -> true)

(** Test empty result when component not registered *)
let test_unregistered_component () =
  let world = create_world_with_components () in
  
  (* Create entity with Position *)
  let e = World.create_entity world in
  World.add_component world e ~name:"Position" { x = 1.0; y = 2.0 };
  
  (* Query for unregistered component *)
  let results = ref 0 in
  Query.from world
  |> Query.with_component "NonExistent"
  |> Query.iter1 (fun _ _ -> incr results);
  
  Alcotest.(check int) "unregistered component should yield 0 results" 0 !results

(** Test suite *)
let tests =
  [
    Alcotest.test_case "iter1 basic" `Quick test_iter1;
    Alcotest.test_case "iter2 basic" `Quick test_iter2;
    Alcotest.test_case "iter1 with having filter" `Quick test_iter1_with_having;
    Alcotest.test_case "iter1 with not_having filter" `Quick test_iter1_with_not_having;
    Alcotest.test_case "count" `Quick test_count;
    Alcotest.test_case "arity mismatch raises error" `Quick test_arity_mismatch;
    Alcotest.test_case "unregistered component" `Quick test_unregistered_component;
  ]

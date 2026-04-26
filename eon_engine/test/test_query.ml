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

(** Test iter1 with having filter *)
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
  Alcotest.(check int) "iter1 with having should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e1, not e2 *)
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e1 should be in results" true (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should not be in results" false (List.mem e2 entity_ids)

(** Test iter1 with not_having filter *)
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
  Alcotest.(check int) "iter1 with not_having should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e2, not e1 *)
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e2 should be in results" true (List.mem e2 entity_ids);
  Alcotest.(check bool) "e1 should not be in results" false (List.mem e1 entity_ids)

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

(** Test count with filters *)
let test_count_with_filters () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Frozen" { value = true };
  
  (* Create entity with Position but not Frozen *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  
  (* Count entities with Position that have Frozen *)
  let count_with_having =
    Query.from world
    |> Query.with_component "Position"
    |> Query.having "Frozen"
    |> Query.count
  in
  Alcotest.(check int) "count with having should return 1" 1 count_with_having;
  
  (* Count entities with Position that do not have Frozen *)
  let count_with_not_having =
    Query.from world
    |> Query.with_component "Position"
    |> Query.not_having "Frozen"
    |> Query.count
  in
  Alcotest.(check int) "count with not_having should return 1" 1 count_with_not_having

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

(** Test with_components (bulk include) *)
let test_with_components () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Velocity *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Velocity" { dx = 0.5; dy = 0.5 };
  
  (* Create entity with only Position *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  
  (* Query using with_components *)
  let results = ref [] in
  Query.from world
  |> Query.with_components ["Position"; "Velocity"]
  |> Query.iter2 (fun entity pos vel ->
    results := (entity, pos, vel) :: !results
  );
  
  (* Should have 1 result (only e1 has both) *)
  Alcotest.(check int) "with_components should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e1 *)
  match !results with
  | [(entity, pos, vel)] ->
      Alcotest.(check bool) "result should be e1" true (Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx
  | _ -> Alcotest.fail "Expected exactly 1 result"

(** Test having_all filter *)
let test_having_all () =
  let world = create_world_with_components () in
  
  (* Create entity with Position, Velocity, and Frozen *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Velocity" { dx = 0.5; dy = 0.5 };
  World.add_component world e1 ~name:"Frozen" { value = true };
  
  (* Create entity with Position and Velocity but not Frozen *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  World.add_component world e2 ~name:"Velocity" { dx = 1.0; dy = 1.0 };
  
  (* Create entity with Position only *)
  let e3 = World.create_entity world in
  World.add_component world e3 ~name:"Position" { x = 5.0; y = 6.0 };
  
  (* Query for entities with Position that also have both Velocity and Frozen *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.having_all ["Velocity"; "Frozen"]
  |> Query.iter1 (fun entity pos ->
    results := (entity, pos) :: !results
  );
  
  (* Should have 1 result (only e1 has all three) *)
  Alcotest.(check int) "having_all should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e1 *)
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e1 should be in results" true (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should not be in results" false (List.mem e2 entity_ids);
  Alcotest.(check bool) "e3 should not be in results" false (List.mem e3 entity_ids)

(** Test not_having_any filter *)
let test_not_having_any () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Frozen" { value = true };
  
  (* Create entity with Position and Health (not Frozen) *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  World.add_component world e2 ~name:"Health" { current = 100; max = 100 };
  
  (* Create entity with Position only *)
  let e3 = World.create_entity world in
  World.add_component world e3 ~name:"Position" { x = 5.0; y = 6.0 };
  
  (* Query for entities with Position that do not have Frozen or Health *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.not_having_any ["Frozen"; "Health"]
  |> Query.iter1 (fun entity pos ->
    results := (entity, pos) :: !results
  );
  
  (* Should have 1 result (only e3 has neither Frozen nor Health) *)
  Alcotest.(check int) "not_having_any should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e3 *)
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e3 should be in results" true (List.mem e3 entity_ids);
  Alcotest.(check bool) "e1 should not be in results" false (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should not be in results" false (List.mem e2 entity_ids)

(** Test iter3 functionality *)
let test_iter3 () =
  let world = create_world_with_components () in
  
  (* Create entity with Position, Velocity, and Health *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Velocity" { dx = 0.5; dy = 0.5 };
  World.add_component world e1 ~name:"Health" { current = 100; max = 100 };
  
  (* Create entity with only two of the three *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  World.add_component world e2 ~name:"Velocity" { dx = 1.0; dy = 1.0 };
  
  (* Query for entities with all three components *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.with_component "Velocity"
  |> Query.with_component "Health"
  |> Query.iter3 (fun entity pos vel health ->
    results := (entity, pos, vel, health) :: !results
  );
  
  (* Should have 1 result (only e1 has all three) *)
  Alcotest.(check int) "iter3 should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e1 *)
  match !results with
  | [(entity, pos, vel, health)] ->
      Alcotest.(check bool) "result should be e1" true (Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx;
      Alcotest.(check int) "health.current" 100 health.current
  | _ -> Alcotest.fail "Expected exactly 1 result"

(** Test iter4 functionality *)
let test_iter4 () =
  let world = create_world_with_components () in
  
  (* Create entity with Position, Velocity, Health, and Frozen *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  World.add_component world e1 ~name:"Velocity" { dx = 0.5; dy = 0.5 };
  World.add_component world e1 ~name:"Health" { current = 100; max = 100 };
  World.add_component world e1 ~name:"Frozen" { value = true };
  
  (* Create entity with only three of the four *)
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  World.add_component world e2 ~name:"Velocity" { dx = 1.0; dy = 1.0 };
  World.add_component world e2 ~name:"Health" { current = 50; max = 100 };
  
  (* Query for entities with all four components *)
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.with_component "Velocity"
  |> Query.with_component "Health"
  |> Query.with_component "Frozen"
  |> Query.iter4 (fun entity pos vel health frozen ->
    results := (entity, pos, vel, health, frozen) :: !results
  );
  
  (* Should have 1 result (only e1 has all four) *)
  Alcotest.(check int) "iter4 should find 1 entity" 1 (List.length !results);
  
  (* Verify the result is e1 *)
  match !results with
  | [(entity, pos, vel, health, frozen)] ->
      Alcotest.(check bool) "result should be e1" true (Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx;
      Alcotest.(check int) "health.current" 100 health.current;
      Alcotest.(check bool) "frozen.value" true frozen.value
  | _ -> Alcotest.fail "Expected exactly 1 result"

(** Test entity lifecycle: created and alive *)
let test_entity_lifecycle_basic () =
  let world = create_world_with_components () in
  
  (* Just verify basic query works with alive entities *)
  let e1 = World.create_entity world in
  World.add_component world e1 ~name:"Position" { x = 1.0; y = 2.0 };
  
  let e2 = World.create_entity world in
  World.add_component world e2 ~name:"Position" { x = 3.0; y = 4.0 };
  
  let results = ref [] in
  Query.from world
  |> Query.with_component "Position"
  |> Query.iter1 (fun entity pos ->
    results := (entity, pos) :: !results
  );
  
  Alcotest.(check int) "finds 2 alive entities" 2 (List.length !results)


(** Test suite *)
let tests =
  [
    Alcotest.test_case "iter1 basic" `Quick test_iter1;
    Alcotest.test_case "iter2 basic" `Quick test_iter2;
    Alcotest.test_case "iter1 with having filter" `Quick test_iter1_with_having;
    Alcotest.test_case "iter1 with not_having filter" `Quick test_iter1_with_not_having;
    Alcotest.test_case "count" `Quick test_count;
    Alcotest.test_case "count with filters" `Quick test_count_with_filters;
    Alcotest.test_case "arity mismatch raises error" `Quick test_arity_mismatch;
    Alcotest.test_case "unregistered component" `Quick test_unregistered_component;
    Alcotest.test_case "with_components (bulk include)" `Quick test_with_components;
    Alcotest.test_case "having_all filter" `Quick test_having_all;
    Alcotest.test_case "not_having_any filter" `Quick test_not_having_any;
    Alcotest.test_case "iter3 basic" `Quick test_iter3;
    Alcotest.test_case "iter4 basic" `Quick test_iter4;
    Alcotest.test_case "entity lifecycle basic" `Quick test_entity_lifecycle_basic;
  ]

(** Tests for Eon Engine Query module *)

open Eon_engine

module Query = Eon_engine.Query.Make(Eon_engine.Sparse_set_backend)

(* ============================================================================ *)
(* Test Components                                                              *)
(* ============================================================================ *)

module Health = struct
  type t = { current : int; max : int }

  let component : t Components.t = Components.component "Health"
  
  let make current max = { current; max }
end

module Frozen = struct
  type t = { value : bool }

  let component : t Components.t = Components.component "Frozen"
  
  let make value = { value }
end

(* ============================================================================ *)
(* Helper Functions                                                             *)
(* ============================================================================ *)

let create_world_with_components () =
  let world = World.create () in
  ignore (World.register world Components.Position.component);
  ignore (World.register world Components.Velocity.component);
  ignore (World.register world Health.component);
  ignore (World.register world Frozen.component);
  world

(* ============================================================================ *)
(* Tests                                                                        *)
(* ============================================================================ *)

let test_iter1 () =
  let world = create_world_with_components () in
  
  (* Create entities with Position component *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  World.add_component world e1 Components.Position.component pos1;

  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;

  (* Create entity without Position *)
  let e3 = World.create_entity world in
  let health = Health.make 100 100 in
  World.add_component world e3 Health.component health;

  (* Query for entities with Position *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.iter1 (fun entity pos -> results := (entity, pos) :: !results);

  (* Assertions *)
  Alcotest.(check int) "iter1 should find 2 entities" 2 (List.length !results);
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e1 should be in results" true (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should be in results" true (List.mem e2 entity_ids);
  Alcotest.(check bool) "e3 should not be in results" false (List.mem e3 entity_ids)


let test_iter2 () =
  let world = create_world_with_components () in
  
  (* Create entity with both Position and Velocity *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  let vel1 : Components.Velocity.t = { dx = 0.5; dy = 0.5 } in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Components.Velocity.component vel1;

  (* Create entity with only Position *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;

  (* Create entity with only Velocity *)
  let e3 = World.create_entity world in
  let vel3 : Components.Velocity.t = { dx = 1.0; dy = 1.0 } in
  World.add_component world e3 Components.Velocity.component vel3;

  (* Query for entities with both Position and Velocity *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.with_component (Components.name Components.Velocity.component)
  |> Query.iter2 (fun entity (pos : Components.Position.t) (vel : Components.Velocity.t) ->
    results := (entity, pos, vel) :: !results);

  (* Assertions *)
  Alcotest.(check int) "iter2 should find 1 entity" 1 (List.length !results);
  match !results with
  | [(entity, pos, vel)] ->
      Alcotest.(check bool) "result should be e1" true (Eon_ecs.Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx
  | _ -> Alcotest.fail "Expected exactly 1 result"


let test_iter1_with_having () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Frozen.component (Frozen.make true);

  (* Create entity with Position but not Frozen *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;

  (* Query for entities with Position that also have Frozen *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.having (Components.name Frozen.component)
  |> Query.iter1 (fun entity pos -> results := (entity, pos) :: !results);

  (* Assertions *)
  Alcotest.(check int) "iter1 with having should find 1 entity" 1 (List.length !results);
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e1 should be in results" true (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should not be in results" false (List.mem e2 entity_ids)


let test_iter1_with_not_having () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Frozen.component (Frozen.make true);

  (* Create entity with Position but not Frozen *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;

  (* Query for entities with Position that do not have Frozen *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.not_having (Components.name Frozen.component)
  |> Query.iter1 (fun entity pos -> results := (entity, pos) :: !results);

  (* Assertions *)
  Alcotest.(check int) "iter1 with not_having should find 1 entity" 1 (List.length !results);
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e2 should be in results" true (List.mem e2 entity_ids);
  Alcotest.(check bool) "e1 should not be in results" false (List.mem e1 entity_ids)


let test_count () =
  let world = create_world_with_components () in
  
  (* Create 3 entities with Position *)
  for i = 1 to 3 do
    let e = World.create_entity world in
    let pos : Components.Position.t = { x = float i; y = float i } in
    World.add_component world e Components.Position.component pos
  done;

  (* Create 1 entity without Position *)
  let e = World.create_entity world in
  let health = Health.make 100 100 in
  World.add_component world e Health.component health;

  (* Count entities with Position *)
  let count =
    Query.from world
    |> Query.with_component (Components.name Components.Position.component)
    |> Query.count
  in

  Alcotest.(check int) "count should return 3" 3 count


let test_count_with_filters () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Frozen.component (Frozen.make true);

  (* Create entity with Position but not Frozen *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;

  (* Count entities with Position that have Frozen *)
  let count_with_having =
    Query.from world
    |> Query.with_component (Components.name Components.Position.component)
    |> Query.having (Components.name Frozen.component)
    |> Query.count
  in
  Alcotest.(check int) "count with having should return 1" 1 count_with_having;

  (* Count entities with Position that do not have Frozen *)
  let count_with_not_having =
    Query.from world
    |> Query.with_component (Components.name Components.Position.component)
    |> Query.not_having (Components.name Frozen.component)
    |> Query.count
  in
  Alcotest.(check int) "count with not_having should return 1" 1 count_with_not_having


let test_arity_mismatch () =
  let world = create_world_with_components () in
  
  (* Try to use iter2 with only one component *)
  let should_raise () =
    Query.from world
    |> Query.with_component (Components.name Components.Position.component)
    |> Query.iter2 (fun _ _ _ -> ())
  in

  Alcotest.(check bool) "iter2 with 1 component should raise" true
    (try should_raise (); false with Invalid_argument _ -> true)


let test_unregistered_component () =
  let world = create_world_with_components () in
  
  (* Create entity with Position *)
  let e = World.create_entity world in
  let pos : Components.Position.t = { x = 1.0; y = 2.0 } in
  World.add_component world e Components.Position.component pos;

  (* Query for unregistered component *)
  let results = ref 0 in
  Query.from world
  |> Query.with_component "NonExistent"
  |> Query.iter1 (fun _ _ -> incr results);

  Alcotest.(check int) "unregistered component should yield 0 results" 0 !results


let test_with_components () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Velocity *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  let vel1 : Components.Velocity.t = { dx = 0.5; dy = 0.5 } in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Components.Velocity.component vel1;

  (* Create entity with only Position *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;

  (* Query using with_components *)
  let results = ref [] in
  Query.from world
  |> Query.with_components [
    Components.name Components.Position.component;
    Components.name Components.Velocity.component
  ]
  |> Query.iter2 (fun entity (pos : Components.Position.t) (vel : Components.Velocity.t) ->
    results := (entity, pos, vel) :: !results);

  (* Assertions *)
  Alcotest.(check int) "with_components should find 1 entity" 1 (List.length !results);
  match !results with
  | [(entity, pos, vel)] ->
      Alcotest.(check bool) "result should be e1" true (Eon_ecs.Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx
  | _ -> Alcotest.fail "Expected exactly 1 result"


let test_having_all () =
  let world = create_world_with_components () in
  
  (* Create entity with Position, Velocity, and Frozen *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  let vel1 : Components.Velocity.t = { dx = 0.5; dy = 0.5 } in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Components.Velocity.component vel1;
  World.add_component world e1 Frozen.component (Frozen.make true);

  (* Create entity with Position and Velocity but not Frozen *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  let vel2 : Components.Velocity.t = { dx = 1.0; dy = 1.0 } in
  World.add_component world e2 Components.Position.component pos2;
  World.add_component world e2 Components.Velocity.component vel2;

  (* Create entity with Position only *)
  let e3 = World.create_entity world in
  let pos3 : Components.Position.t = { x = 5.0; y = 6.0 } in
  World.add_component world e3 Components.Position.component pos3;

  (* Query for entities with Position that also have both Velocity and Frozen *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.having_all [
    Components.name Components.Velocity.component;
    Components.name Frozen.component
  ]
  |> Query.iter1 (fun entity pos -> results := (entity, pos) :: !results);

  (* Assertions *)
  Alcotest.(check int) "having_all should find 1 entity" 1 (List.length !results);
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e1 should be in results" true (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should not be in results" false (List.mem e2 entity_ids);
  Alcotest.(check bool) "e3 should not be in results" false (List.mem e3 entity_ids)


let test_not_having_any () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and Frozen *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Frozen.component (Frozen.make true);

  (* Create entity with Position and Health (not Frozen) *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;
  let health = Health.make 100 100 in
  World.add_component world e2 Health.component health;

  (* Create entity with Position only *)
  let e3 = World.create_entity world in
  let pos3 : Components.Position.t = { x = 5.0; y = 6.0 } in
  World.add_component world e3 Components.Position.component pos3;

  (* Query for entities with Position that do not have Frozen or Health *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.not_having_any [
    Components.name Frozen.component;
    Components.name Health.component
  ]
  |> Query.iter1 (fun entity pos -> results := (entity, pos) :: !results);

  (* Assertions *)
  Alcotest.(check int) "not_having_any should find 1 entity" 1 (List.length !results);
  let entity_ids = List.map fst !results in
  Alcotest.(check bool) "e3 should be in results" true (List.mem e3 entity_ids);
  Alcotest.(check bool) "e1 should not be in results" false (List.mem e1 entity_ids);
  Alcotest.(check bool) "e2 should not be in results" false (List.mem e2 entity_ids)


let test_iter3 () =
  let world = create_world_with_components () in
  
  (* Create entity with Position, Velocity, and Health *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  let vel1 : Components.Velocity.t = { dx = 0.5; dy = 0.5 } in
  let health1 = Health.make 100 100 in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Components.Velocity.component vel1;
  World.add_component world e1 Health.component health1;

  (* Create entity with only two of the three *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  let vel2 : Components.Velocity.t = { dx = 1.0; dy = 1.0 } in
  World.add_component world e2 Components.Position.component pos2;
  World.add_component world e2 Components.Velocity.component vel2;

  (* Query for entities with all three components *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.with_component (Components.name Components.Velocity.component)
  |> Query.with_component (Components.name Health.component)
  |> Query.iter3 (fun entity (pos : Components.Position.t) (vel : Components.Velocity.t) (health : Health.t) ->
    results := (entity, pos, vel, health) :: !results);

  (* Assertions *)
  Alcotest.(check int) "iter3 should find 1 entity" 1 (List.length !results);
  match !results with
  | [(entity, pos, vel, health)] ->
      Alcotest.(check bool) "result should be e1" true (Eon_ecs.Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx;
      Alcotest.(check int) "health.current" 100 health.current
  | _ -> Alcotest.fail "Expected exactly 1 result"


let test_iter4 () =
  let world = create_world_with_components () in
  
  (* Create entity with Position, Velocity, Health, and Frozen *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  let vel1 : Components.Velocity.t = { dx = 0.5; dy = 0.5 } in
  let health1 = Health.make 100 100 in
  World.add_component world e1 Components.Position.component pos1;
  World.add_component world e1 Components.Velocity.component vel1;
  World.add_component world e1 Health.component health1;
  World.add_component world e1 Frozen.component (Frozen.make true);

  (* Create entity with only three of the four *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  let vel2 : Components.Velocity.t = { dx = 1.0; dy = 1.0 } in
  let health2 = Health.make 50 100 in
  World.add_component world e2 Components.Position.component pos2;
  World.add_component world e2 Components.Velocity.component vel2;
  World.add_component world e2 Health.component health2;

  (* Query for entities with all four components *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.with_component (Components.name Components.Velocity.component)
  |> Query.with_component (Components.name Health.component)
  |> Query.with_component (Components.name Frozen.component)
  |> Query.iter4 (fun entity (pos : Components.Position.t) (vel : Components.Velocity.t) (health : Health.t) (frozen : Frozen.t) ->
    results := (entity, pos, vel, health, frozen) :: !results);

  (* Assertions *)
  Alcotest.(check int) "iter4 should find 1 entity" 1 (List.length !results);
  match !results with
  | [(entity, pos, vel, health, frozen)] ->
      Alcotest.(check bool) "result should be e1" true (Eon_ecs.Entity_id.equal entity e1);
      Alcotest.(check (float 0.001)) "pos.x" 1.0 pos.x;
      Alcotest.(check (float 0.001)) "vel.dx" 0.5 vel.dx;
      Alcotest.(check int) "health.current" 100 health.current;
      Alcotest.(check bool) "frozen.value" true frozen.value
  | _ -> Alcotest.fail "Expected exactly 1 result"


let test_destroyed_entity_removal () =
  let world = create_world_with_components () in
  
  (* Create entity with Position and destroy it *)
  let e1 = World.create_entity world in
  let pos1 : Components.Position.t = { x = 1.0; y = 2.0 } in
  World.add_component world e1 Components.Position.component pos1;
  World.destroy_entity world e1;

  (* Create second entity with Position (should be at same index if freed) *)
  let e2 = World.create_entity world in
  let pos2 : Components.Position.t = { x = 3.0; y = 4.0 } in
  World.add_component world e2 Components.Position.component pos2;

  (* Query for entities with Position - should only find e2 *)
  let results = ref [] in
  Query.from world
  |> Query.with_component (Components.name Components.Position.component)
  |> Query.iter1 (fun entity (pos : Components.Position.t) -> results := (entity, pos) :: !results);

  (* Assertions *)
  Alcotest.(check int) "destroyed entity removed from sparse set" 1 (List.length !results);
  match !results with
  | [(entity, pos)] ->
      Alcotest.(check bool) "result should be e2" true (Eon_ecs.Entity_id.equal entity e2);
      Alcotest.(check (float 0.001)) "pos.x" 3.0 pos.x
  | _ -> Alcotest.fail "Expected exactly 1 result"


(* ============================================================================ *)
(* Test Suite Registration                                                      *)
(* ============================================================================ *)

let tests = [
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
  Alcotest.test_case "destroyed entity removal" `Quick test_destroyed_entity_removal;
]

(** Tests for Eon Engine Query module *)

open Eon_engine

module Q = Eon_engine.Query.Make(Eon_engine.Sparse_set_backend.Default)

module Health = struct
  type t = { current : int; max : int }
  let component : t Components.t = Components.component "Health"
  let make current max = { current; max }
end

module Frozen = struct
  type t = unit
  let component : t Components.t = Components.component "Frozen"
end

let create_world () =
  let world = World.create () in
  ignore (World.register world Components.Position.component);
  ignore (World.register world Components.Velocity.component);
  ignore (World.register world Health.component);
  ignore (World.register world Frozen.component);
  world

(* ── iter ── *)

let pos x y : Components.Position.t = { x; y }
let vel dx dy : Components.Velocity.t = { dx; dy }

let test_iter_single () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let e3 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 2.0);
  World.add_component world e2 Components.Position.component (pos 3.0 4.0);
  World.add_component world e3 Health.component (Health.make 100 100);
  let seen = ref [] in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.iter (fun view -> seen := View.entity view :: !seen);
  Alcotest.(check int) "two entities with Position" 2 (List.length !seen);
  Alcotest.(check bool) "e1 found" true (List.mem e1 !seen);
  Alcotest.(check bool) "e2 found" true (List.mem e2 !seen);
  Alcotest.(check bool) "e3 not found" false (List.mem e3 !seen)

let test_iter_two_components () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let e3 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 2.0);
  World.add_component world e1 Components.Velocity.component (vel 0.5 0.5);
  World.add_component world e2 Components.Position.component (pos 3.0 4.0);
  World.add_component world e3 Components.Velocity.component (vel 1.0 1.0);
  let seen = ref [] in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.having Components.Velocity.name
  |> Q.iter (fun view ->
       let (p : Components.Position.t) = View.get view (module Components.Position) in
       let (v : Components.Velocity.t) = View.get view (module Components.Velocity) in
       seen := (View.entity view, p, v) :: !seen);
  Alcotest.(check int) "one entity with both" 1 (List.length !seen);
  match !seen with
  | [(entity, p, v)] ->
    Alcotest.(check bool) "is e1" true (Eon_ecs.Entity_id.equal entity e1);
    Alcotest.(check (float 0.001)) "pos.x" 1.0 p.x;
    Alcotest.(check (float 0.001)) "vel.dx" 0.5 v.dx
  | _ -> Alcotest.fail "expected exactly 1 result"

let test_iter_with_having_filter () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 2.0);
  World.add_component world e1 Frozen.component ();
  World.add_component world e2 Components.Position.component (pos 3.0 4.0);
  let seen = ref [] in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.having Frozen.component
  |> Q.iter (fun view -> seen := View.entity view :: !seen);
  Alcotest.(check int) "one entity (frozen)" 1 (List.length !seen);
  Alcotest.(check bool) "e1 found" true (List.mem e1 !seen);
  Alcotest.(check bool) "e2 not found" false (List.mem e2 !seen)

let test_iter_with_not_having_filter () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 2.0);
  World.add_component world e1 Frozen.component ();
  World.add_component world e2 Components.Position.component (pos 3.0 4.0);
  let seen = ref [] in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.not_having Frozen.component
  |> Q.iter (fun view -> seen := View.entity view :: !seen);
  Alcotest.(check int) "one entity (not frozen)" 1 (List.length !seen);
  Alcotest.(check bool) "e2 found" true (List.mem e2 !seen);
  Alcotest.(check bool) "e1 not found" false (List.mem e1 !seen)

let test_having_all () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let e3 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 2.0);
  World.add_component world e1 Components.Velocity.component (vel 0.5 0.5);
  World.add_component world e1 Frozen.component ();
  World.add_component world e2 Components.Position.component (pos 3.0 4.0);
  World.add_component world e2 Components.Velocity.component (vel 1.0 1.0);
  World.add_component world e3 Components.Position.component (pos 5.0 6.0);
  let seen = ref [] in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.having_all [Components.Velocity.name; Frozen.component]
  |> Q.iter (fun view -> seen := View.entity view :: !seen);
  Alcotest.(check int) "one entity has all three" 1 (List.length !seen);
  Alcotest.(check bool) "e1 found" true (List.mem e1 !seen);
  Alcotest.(check bool) "e2 not found" false (List.mem e2 !seen);
  Alcotest.(check bool) "e3 not found" false (List.mem e3 !seen)

let test_not_having_any () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let e3 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 2.0);
  World.add_component world e1 Frozen.component ();
  World.add_component world e2 Components.Position.component (pos 3.0 4.0);
  World.add_component world e2 Health.component (Health.make 100 100);
  World.add_component world e3 Components.Position.component (pos 5.0 6.0);
  let seen = ref [] in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.not_having_any [Frozen.component; Health.component]
  |> Q.iter (fun view -> seen := View.entity view :: !seen);
  Alcotest.(check int) "one entity has neither" 1 (List.length !seen);
  Alcotest.(check bool) "e3 found" true (List.mem e3 !seen);
  Alcotest.(check bool) "e1 not found" false (List.mem e1 !seen);
  Alcotest.(check bool) "e2 not found" false (List.mem e2 !seen)

let test_five_components () =
  let world = World.create () in
  let names = ["A"; "B"; "C"; "D"; "E"] in
  let descs = List.map (fun n -> Components.component n) names in
  List.iter (fun d -> ignore (World.register world d)) descs;
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  List.iter (fun d -> World.add_component world e1 d 1) descs;
  List.iter (fun d -> World.add_component world e2 d 1)
    (List.filteri (fun i _ -> i < 4) descs);  (* e2 missing E *)
  let seen = ref [] in
  Q.from world
  |> Q.having_all names
  |> Q.iter (fun view -> seen := View.entity view :: !seen);
  Alcotest.(check int) "only e1 has all 5" 1 (List.length !seen);
  Alcotest.(check bool) "e1 found" true (List.mem e1 !seen)

let test_count () =
  let world = create_world () in
  for i = 1 to 3 do
    let e = World.create_entity world in
    World.add_component world e Components.Position.component (pos (float i) 0.0)
  done;
  let e = World.create_entity world in
  World.add_component world e Health.component (Health.make 100 100);
  let n = Q.from world |> Q.having Components.Position.name |> Q.count in
  Alcotest.(check int) "count 3 entities with Position" 3 n

let test_count_with_filters () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 0.0);
  World.add_component world e1 Frozen.component ();
  World.add_component world e2 Components.Position.component (pos 2.0 0.0);
  let n_having =
    Q.from world
    |> Q.having Components.Position.name
    |> Q.having Frozen.component
    |> Q.count in
  Alcotest.(check int) "count with having" 1 n_having;
  let n_not_having =
    Q.from world
    |> Q.having Components.Position.name
    |> Q.not_having Frozen.component
    |> Q.count in
  Alcotest.(check int) "count with not_having" 1 n_not_having

let test_unregistered_raises () =
  let world = create_world () in
  Alcotest.check_raises
    "unregistered component raises Invalid_argument"
    (Invalid_argument "iter_entities: unregistered component: NonExistent")
    (fun () ->
      Q.from world
      |> Q.having "NonExistent"
      |> Q.iter (fun _ -> ()))

let test_destroyed_entity_not_visited () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 0.0);
  World.add_component world e2 Components.Position.component (pos 3.0 0.0);
  World.destroy_entity world e1;
  let seen = ref [] in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.iter (fun view -> seen := View.entity view :: !seen);
  Alcotest.(check int) "destroyed entity not visited" 1 (List.length !seen);
  Alcotest.(check bool) "e2 found" true (List.mem e2 !seen)

(* ── View ── *)

let test_view_get () =
  let world = create_world () in
  let e = World.create_entity world in
  ignore e;
  World.add_component world e Components.Position.component (pos 7.0 3.0);
  Q.from world
  |> Q.having Components.Position.name
  |> Q.iter (fun view ->
       let (p : Components.Position.t) = View.get view (module Components.Position) in
       Alcotest.(check (float 0.001)) "View.get x" 7.0 p.x;
       Alcotest.(check (float 0.001)) "View.get y" 3.0 p.y)

let test_view_get_raises_on_absent () =
  let world = create_world () in
  let e = World.create_entity world in
  World.add_component world e Components.Position.component (pos 0.0 0.0);
  Q.from world
  |> Q.having Components.Position.name
  |> Q.iter (fun view ->
       Alcotest.check_raises
         "View.get raises on absent component"
         (Invalid_argument "View.get: component absent: Velocity")
         (fun () -> ignore (View.get view (module Components.Velocity))))

let test_view_get_opt () =
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 Components.Position.component (pos 1.0 0.0);
  World.add_component world e1 Components.Velocity.component (vel 5.0 0.0);
  World.add_component world e2 Components.Position.component (pos 2.0 0.0);
  let with_vel = ref 0 and without_vel = ref 0 in
  Q.from world
  |> Q.having Components.Position.name
  |> Q.iter (fun view ->
       match View.get_opt view (module Components.Velocity) with
       | Some _ -> incr with_vel
       | None   -> incr without_vel);
  Alcotest.(check int) "one entity has vel" 1 !with_vel;
  Alcotest.(check int) "one entity lacks vel" 1 !without_vel

let test_view_entity () =
  let world = create_world () in
  let e = World.create_entity world in
  World.add_component world e Components.Position.component (pos 0.0 0.0);
  Q.from world
  |> Q.having Components.Position.name
  |> Q.iter (fun view ->
       Alcotest.(check bool) "View.entity matches"
         true (Eon_ecs.Entity_id.equal (View.entity view) e))

let tests = [
  Alcotest.test_case "iter1 basic"                `Quick test_iter_single;
  Alcotest.test_case "iter2 basic"                `Quick test_iter_two_components;
  Alcotest.test_case "iter1 with having filter"   `Quick test_iter_with_having_filter;
  Alcotest.test_case "iter1 with not_having filter" `Quick test_iter_with_not_having_filter;
  Alcotest.test_case "having_all filter"          `Quick test_having_all;
  Alcotest.test_case "not_having_any filter"      `Quick test_not_having_any;
  Alcotest.test_case "5+ component query"         `Quick test_five_components;
  Alcotest.test_case "count"                      `Quick test_count;
  Alcotest.test_case "count with filters"         `Quick test_count_with_filters;
  Alcotest.test_case "unregistered component"     `Quick test_unregistered_raises;
  Alcotest.test_case "destroyed entity removal"   `Quick test_destroyed_entity_not_visited;
  Alcotest.test_case "View.get"                   `Quick test_view_get;
  Alcotest.test_case "View.get raises on absent"  `Quick test_view_get_raises_on_absent;
  Alcotest.test_case "View.get_opt"               `Quick test_view_get_opt;
  Alcotest.test_case "View.entity"                `Quick test_view_entity;
]

open Eon_engine

module Health = struct
  type t = { hp : int }
  let component : t Components.t = Components.component "View_test_health"
  let name = "View_test_health"
end

module Tag = struct
  type t = unit
  let component : t Components.t = Components.component "View_test_tag"
  let name = "View_test_tag"
end

let create_world () =
  let world = World.create () in
  ignore (World.register world Health.component);
  ignore (World.register world Tag.component);
  world

let test_entity_returns_correct_id () =
  let world = create_world () in
  let e = World.create_entity world in
  let view = View.make world e in
  Alcotest.(check bool) "entity id matches" true (View.entity view = e)

let test_get_returns_component_value () =
  let world = create_world () in
  let e = World.create_entity world in
  World.add_component world e Health.component Health.{ hp = 42 };
  let view = View.make world e in
  let (h : Health.t) = View.get view (module Health) in
  Alcotest.(check int) "get returns stored value" 42 h.hp

let test_get_raises_on_absent () =
  let world = create_world () in
  let e = World.create_entity world in
  let view = View.make world e in
  Alcotest.check_raises "get raises Invalid_argument when absent"
    (Invalid_argument "View.get: component absent: View_test_health")
    (fun () -> ignore (View.get view (module Health)))

let test_get_opt_returns_some_when_present () =
  let world = create_world () in
  let e = World.create_entity world in
  World.add_component world e Health.component Health.{ hp = 7 };
  let view = View.make world e in
  match View.get_opt view (module Health) with
  | Some (h : Health.t) -> Alcotest.(check int) "get_opt Some value" 7 h.hp
  | None   -> Alcotest.fail "expected Some, got None"

let test_get_opt_returns_none_when_absent () =
  let world = create_world () in
  let e = World.create_entity world in
  let view = View.make world e in
  Alcotest.(check bool) "get_opt None when absent"
    true (View.get_opt view (module Health) = None)

let test_get_opt_absent_does_not_affect_present () =
  let world = create_world () in
  let e = World.create_entity world in
  World.add_component world e Health.component Health.{ hp = 99 };
  let view = View.make world e in
  Alcotest.(check bool) "Tag absent" true (View.get_opt view (module Tag) = None);
  let (h : Health.t) = View.get view (module Health) in
  Alcotest.(check int) "Health still readable" 99 h.hp

let tests = [
  "View — entity returns correct id",              `Quick, test_entity_returns_correct_id;
  "View — get returns component value",            `Quick, test_get_returns_component_value;
  "View — get raises on absent component",         `Quick, test_get_raises_on_absent;
  "View — get_opt returns Some when present",      `Quick, test_get_opt_returns_some_when_present;
  "View — get_opt returns None when absent",       `Quick, test_get_opt_returns_none_when_absent;
  "View — get_opt absent does not affect present", `Quick, test_get_opt_absent_does_not_affect_present;
]

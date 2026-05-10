open Eon_engine

let test_world_register () =
  let world = World.create () in
  let comp = component "Test" in
  let result = World.register world comp in
  match result with
  | Components.Registered -> ()
  | Components.Already_registered -> failwith "Should be registered"

let test_world_is_registered () =
  let world = World.create () in
  let comp = component "Test" in
  let is_reg = World.is_registered world comp in
  Alcotest.(check bool) "not registered initially" false is_reg

let test_world_count_entities () =
  let world = World.create () in
  let count = World.count_entities world in
  Alcotest.(check int) "count is 0" 0 count

let test_world_is_alive () =
  let world = World.create () in
  let entity = World.create_entity world in
  let is_alive = World.is_alive world entity in
  Alcotest.(check bool) "entity is alive" true is_alive

let tests = [
  "World.register", `Quick, test_world_register;
  "World.is_registered", `Quick, test_world_is_registered;
  "World.count_entities", `Quick, test_world_count_entities;
  "World.is_alive", `Quick, test_world_is_alive;
]

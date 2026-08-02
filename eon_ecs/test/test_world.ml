open Alcotest

module World = Eon_ecs__World
module Query = Eon_ecs__Query
let hash_key key =
  Hashtbl.hash key land Stdlib.max_int

let int_pair = pair int int

let register_default_components world =
  ignore (World.register_component world ~name:"Position" ~id:0);
  ignore (World.register_component world ~name:"Velocity" ~id:1)

let test_entity_lifecycle () =
  let world = World.create () in
  let e = World.create_entity world in
  check int "entity count after create" 1 (World.count_entities world);
  check bool "entity alive" true (World.is_alive world e);

  World.destroy_entity world e;
  check bool "entity dead" false (World.is_alive world e);
  check int "entity count after destroy" 0 (World.count_entities world)

let test_destroy_removes_components () =
  let world = World.create () in
  register_default_components world;
  let e = World.create_entity world in
  World.add_component world e ~name:"Position" (1, 1);
  World.add_component world e ~name:"Velocity" (2, 2);
  
  (* Verify components are registered *)
  check int "position count = 1" 1 (Query.count world [ "Position" ]);
  check int "velocity count = 1" 1 (Query.count world [ "Velocity" ]);
  
  (* Destroy entity - components should be removed *)
  World.destroy_entity world e;
  
  (* Verify components are removed from sparse sets *)
  check int "position count = 0 after destroy" 0 (Query.count world [ "Position" ]);
  check int "velocity count = 0 after destroy" 0 (Query.count world [ "Velocity" ])

let test_component_crud () =
  let world = World.create () in
  register_default_components world;
  let e = World.create_entity world in

  World.add_component world e ~name:"Position" (1, 1);
  check int "position count = 1" 1 (Query.count world [ "Position" ]);

  let pos =
    World.get_component world e ~name:"Position"
    |> Option.value ~default:(-1, -1)
  in
  check int_pair "position fetched" (1, 1) pos;

  World.set_component world e ~name:"Position" (2, 3);
  let pos' =
    World.get_component world e ~name:"Position"
    |> Option.value ~default:(-1, -1)
  in
  check int_pair "position updated" (2, 3) pos';
  check int "position still unique" 1 (Query.count world [ "Position" ]);

  World.add_component world e ~name:"Velocity" (1, 0);
  World.remove_component world e ~name:"Velocity";
  let has_velocity =
    World.get_component world e ~name:"Velocity" |> Option.is_some
  in
  check bool "velocity removed" false has_velocity;

  World.remove_component world e ~name:"Position";
  check int "position removed" 0 (Query.count world [ "Position" ])

let test_remove_all_components () =
  let world = World.create () in
  register_default_components world;
  let e = World.create_entity world in
  World.add_component world e ~name:"Position" (5, 5);
  World.add_component world e ~name:"Velocity" (0, -1);

  World.remove_all_components world e;
  check int "no positions remain" 0 (Query.count world [ "Position" ]);
  check int "no velocities remain" 0 (Query.count world [ "Velocity" ])

let test_data_store () =
  let world = World.create () in
  World.add_data world `Score 10;
  check int "data count" 1 (World.count_data world);
  let score = World.get_data world `Score |> Option.value ~default:0 in
  check int "score fetched" 10 score;

  World.add_data world `Best 42;
  let best = World.get_data world `Best |> Option.value ~default:0 in
  check int "second value fetched" 42 best;
  check int "data count two entries" 2 (World.count_data world)

let test_services () =
  let world = World.create () in
  World.add_service world `Audio 7;
  World.add_service world `Input "keyboard";

  let audio = World.get_service world `Audio |> Option.value ~default:(-1) in
  check int "service lookup" 7 audio;
  let input =
    World.get_service world `Input |> Option.value ~default:""
  in
  check string "service lookup (string)" "keyboard" input;

  let services = World.list_services world in
  check int "service count" 2 (List.length services);
  check bool "contains Audio" true (List.mem (hash_key `Audio) services);
  check bool "contains Input" true (List.mem (hash_key `Input) services)

let test_component_generation_bumps_on_membership_change () =
  let world = World.create () in
  register_default_components world;
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  let v0 = World.component_generation world "Position" in
  World.add_component world e1 ~name:"Position" (1, 1);
  let v1 = World.component_generation world "Position" in
  check bool "version bumped on add" true (v1 > v0);

  (* set_component on an already-present component changes a value, not
     membership -- must not bump. *)
  World.set_component world e1 ~name:"Position" (2, 2);
  check int "version unchanged on set_component" v1
    (World.component_generation world "Position");

  (* Same-tick swap: remove one entity's component, add a different
     entity's, in the same "tick" -- a length/count-based staleness proxy
     would see the count return to its prior value and wrongly think
     nothing changed. The generation counter must still bump on both
     operations. *)
  World.remove_component world e1 ~name:"Position";
  let v2 = World.component_generation world "Position" in
  check bool "version bumped on remove" true (v2 > v1);
  World.add_component world e2 ~name:"Position" (3, 3);
  let v3 = World.component_generation world "Position" in
  check bool "version bumped again on same-tick swap re-add" true (v3 > v2)

let test_component_generation_raises_on_unregistered () =
  let world = World.create () in
  check_raises "unregistered component"
    (Failure "Unknown component: Position")
    (fun () -> ignore (World.component_generation world "Position"))

let tests =
  [
    test_case "entity lifecycle" `Quick test_entity_lifecycle;
    test_case "destroy removes components" `Quick test_destroy_removes_components;
    test_case "component CRUD" `Quick test_component_crud;
    test_case "remove_all_components" `Quick test_remove_all_components;
    test_case "data store operations" `Quick test_data_store;
    test_case "service store operations" `Quick test_services;
    test_case "component_generation bumps on membership change" `Quick
      test_component_generation_bumps_on_membership_change;
    test_case "component_generation raises on unregistered" `Quick
      test_component_generation_raises_on_unregistered;
  ]

module World = Eon_ecs__World
module Query = Eon_ecs__Query

module Int_map = Map.Make (Int)

type component_op =
  | Add_component of int * int
  | Set_component of int * int
  | Remove_component of int

let pp_component_op = function
  | Add_component (selector, value) ->
      Printf.sprintf "add_component(%d,%d)" selector value
  | Set_component (selector, value) ->
      Printf.sprintf "set_component(%d,%d)" selector value
  | Remove_component selector ->
      Printf.sprintf "remove_component(%d)" selector

let gen_component_op =
  let open QCheck.Gen in
  oneof_weighted
    [
      (4, map2 (fun s v -> Add_component (s, v)) (int_bound 127) int);
      (4, map2 (fun s v -> Set_component (s, v)) (int_bound 127) int);
      (2, map (fun s -> Remove_component s) (int_bound 127));
    ]

let arb_component_ops =
  QCheck.make
    ~print:(QCheck.Print.list pp_component_op)
    (QCheck.Gen.list_size (QCheck.Gen.int_bound 300) gen_component_op)

let check_component_world world entities model =
  let entity_count = Array.length entities in
  let rec loop i =
    if i >= entity_count then true
    else
      let entity = entities.(i) in
      let expected = Int_map.find_opt i model in
      let actual = World.get_component world entity ~name:"Health" in
      if actual = expected then loop (i + 1) else false
  in
  let query_count_ok = Query.count world [ "Health" ] = Int_map.cardinal model in
  query_count_ok && loop 0

let prop_world_component_round_trip =
  let test_fn ops =
    let world = World.create () in
    ignore (World.register_component world ~name:"Health" ~id:0);
    let entities = Array.init 32 (fun _ -> World.create_entity world) in
    let entity_count = Array.length entities in
    let apply model = function
      | Add_component (selector, value) ->
          let slot = selector mod entity_count in
          World.add_component world entities.(slot) ~name:"Health" value;
          Int_map.add slot value model
      | Set_component (selector, value) ->
          let slot = selector mod entity_count in
          World.set_component world entities.(slot) ~name:"Health" value;
          Int_map.add slot value model
      | Remove_component selector ->
          let slot = selector mod entity_count in
          World.remove_component world entities.(slot) ~name:"Health";
          Int_map.remove slot model
    in
    let model = List.fold_left apply Int_map.empty ops in
    check_component_world world entities model
  in
  QCheck.Test.make
    ~name:"World component round-trip"
    ~count:1_000
    arb_component_ops
    test_fn

type resource_op =
  | Put_data of int * int
  | Put_service of int * int

let pp_resource_op = function
  | Put_data (k, v) -> Printf.sprintf "put_data(%d,%d)" k v
  | Put_service (k, v) -> Printf.sprintf "put_service(%d,%d)" k v

let data_key = function
  | 0 -> `Data0
  | 1 -> `Data1
  | 2 -> `Data2
  | 3 -> `Data3
  | 4 -> `Data4
  | 5 -> `Data5
  | 6 -> `Data6
  | _ -> `Data7

let service_key = function
  | 0 -> `Service0
  | 1 -> `Service1
  | 2 -> `Service2
  | 3 -> `Service3
  | 4 -> `Service4
  | 5 -> `Service5
  | 6 -> `Service6
  | _ -> `Service7

let gen_resource_op =
  let open QCheck.Gen in
  oneof_weighted
    [
      (1, map2 (fun k v -> Put_data (k, v)) (int_bound 7) int);
      (1, map2 (fun k v -> Put_service (k, v)) (int_bound 7) int);
    ]

let arb_resource_ops =
  QCheck.make
    ~print:(QCheck.Print.list pp_resource_op)
    (QCheck.Gen.list_size (QCheck.Gen.int_bound 300) gen_resource_op)

let check_resource_world world data_model service_model =
  let data_count_ok = World.count_data world = Int_map.cardinal data_model in
  let services = World.list_services world in
  let service_count_ok = List.length services = Int_map.cardinal service_model in
  let data_entries_ok =
    Int_map.for_all
      (fun k v -> World.get_data world (data_key k) = Some v)
      data_model
  in
  let service_entries_ok =
    Int_map.for_all
      (fun k v -> World.get_service world (service_key k) = Some v)
      service_model
  in
  data_count_ok && service_count_ok && data_entries_ok && service_entries_ok

let prop_world_resource_round_trip =
  let test_fn ops =
    let world = World.create () in
    let apply (data_model, service_model) = function
      | Put_data (k, v) ->
          World.add_data world (data_key k) v;
          (Int_map.add k v data_model, service_model)
      | Put_service (k, v) ->
          World.add_service world (service_key k) v;
          (data_model, Int_map.add k v service_model)
    in
    let data_model, service_model =
      List.fold_left apply (Int_map.empty, Int_map.empty) ops
    in
    check_resource_world world data_model service_model
  in
  QCheck.Test.make
    ~name:"World resource round-trip"
    ~count:1_000
    arb_resource_ops
    test_fn

let tests =
  [
    QCheck_alcotest.to_alcotest prop_world_component_round_trip;
    QCheck_alcotest.to_alcotest prop_world_resource_round_trip;
  ]

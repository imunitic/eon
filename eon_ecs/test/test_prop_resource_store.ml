module Resource_store = Eon_ecs__Resource_store

(* A fixed, closed set of top-level polymorphic variant constants — per
   CLAUDE.md's resource-store note, constant constructors are the clean way
   to get stable key identity ([Resource_store] keys on [Obj.repr]). *)
let key_of_index = function
  | 0 -> `K0
  | 1 -> `K1
  | 2 -> `K2
  | 3 -> `K3
  | 4 -> `K4
  | _ -> `K5

let key_count = 6

module Int_map = Map.Make (Int)

type op =
  | Add of int * int
  | Remove of int

let gen_op =
  let open QCheck.Gen in
  let gen_key = int_range 0 (key_count - 1) in
  oneof_weighted
    [
      (3, map2 (fun k v -> Add (k, v)) gen_key int);
      (1, map (fun k -> Remove k) gen_key);
    ]

let pp_op = function
  | Add (k, v) -> Printf.sprintf "add(%d,%d)" k v
  | Remove k -> Printf.sprintf "remove(%d)" k

let arb_ops = QCheck.make ~print:(QCheck.Print.list pp_op)
    (QCheck.Gen.list_size (QCheck.Gen.int_bound 200) gen_op)

(* ------------------------------------------------------------------ *)
(* Data plane                                                          *)
(* ------------------------------------------------------------------ *)

let prop_data_plane_matches_model =
  let test_fn ops =
    let store = Resource_store.create () in
    let model =
      List.fold_left
        (fun model -> function
          | Add (k, v) ->
              Resource_store.add_data store (key_of_index k) v;
              Int_map.add k v model
          | Remove k ->
              Resource_store.remove_data store (key_of_index k);
              Int_map.remove k model)
        Int_map.empty ops
    in
    let state_matches =
      List.init key_count (fun k -> k)
      |> List.for_all (fun k ->
             (Resource_store.get_data store (key_of_index k) : int option) = Int_map.find_opt k model)
    in
    let count_matches = Resource_store.count_data store = Int_map.cardinal model in
    (* [iter_data]'s key argument is an internal int id, not our variant
       index — only the cardinality visited is meaningfully comparable here. *)
    let iter_visited_count =
      let visited_count = ref 0 in
      Resource_store.iter_data (fun _ _ -> incr visited_count) store;
      !visited_count
    in
    let iter_matches = iter_visited_count = Int_map.cardinal model in
    state_matches && count_matches && iter_matches
  in
  QCheck.Test.make ~name:"Resource_store data plane matches a reference model"
    ~count:1_000 arb_ops test_fn

(* ------------------------------------------------------------------ *)
(* Service plane                                                       *)
(* ------------------------------------------------------------------ *)

let prop_service_plane_matches_model =
  let test_fn ops =
    let store = Resource_store.create () in
    let model =
      List.fold_left
        (fun model -> function
          | Add (k, v) ->
              Resource_store.add_service store (key_of_index k) v;
              Int_map.add k v model
          | Remove k ->
              Resource_store.remove_service store (key_of_index k);
              Int_map.remove k model)
        Int_map.empty ops
    in
    let state_matches =
      List.init key_count (fun k -> k)
      |> List.for_all (fun k ->
             (Resource_store.get_service store (key_of_index k) : int option)
             = Int_map.find_opt k model)
    in
    let services_count_matches =
      List.length (Resource_store.list_services store) = Int_map.cardinal model
    in
    state_matches && services_count_matches
  in
  QCheck.Test.make ~name:"Resource_store service plane matches a reference model"
    ~count:1_000 arb_ops test_fn

(* ------------------------------------------------------------------ *)
(* Independence: data-plane operations never leak into the service     *)
(* plane and vice versa (documented as "a naming convention... not an  *)
(* enforced distinction" but backed by separate internal storage).     *)
(* ------------------------------------------------------------------ *)

let prop_planes_are_independent =
  let test_fn ops =
    let store = Resource_store.create () in
    List.iter
      (function
        | Add (k, v) -> Resource_store.add_data store (key_of_index k) v
        | Remove k -> Resource_store.remove_data store (key_of_index k))
      ops;
    (* No service was ever added, so every key must still read back None
       on the service plane no matter what happened on the data plane. *)
    List.init key_count (fun k -> k)
    |> List.for_all (fun k -> (Resource_store.get_service store (key_of_index k) : int option) = None)
  in
  QCheck.Test.make ~name:"Resource_store data-plane operations never affect the service plane"
    ~count:500 arb_ops test_fn

let tests =
  [
    QCheck_alcotest.to_alcotest prop_data_plane_matches_model;
    QCheck_alcotest.to_alcotest prop_service_plane_matches_model;
    QCheck_alcotest.to_alcotest prop_planes_are_independent;
  ]

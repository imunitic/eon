module Sparse_set = Eon_ecs__Sparse_set
module Entity_id = Eon_ecs__Entity_id

module Int_map = Map.Make (Int)

type op =
  | Add of int * int
  | Set_value of int * int
  | Remove of int

let max_entity_index = 63

let entity_of_index i = Entity_id.make i 0

let gen_op =
  let open QCheck.Gen in
  let gen_idx = int_range 0 max_entity_index in
  frequency
    [
      (4, map2 (fun idx v -> Add (idx, v)) gen_idx int);
      (4, map2 (fun idx v -> Set_value (idx, v)) gen_idx int);
      (2, map (fun idx -> Remove idx) gen_idx);
    ]

let pp_op = function
  | Add (idx, v) -> Printf.sprintf "add(%d,%d)" idx v
  | Set_value (idx, v) -> Printf.sprintf "set_value(%d,%d)" idx v
  | Remove idx -> Printf.sprintf "remove(%d)" idx

let arb_ops =
  QCheck.make
    ~print:(QCheck.Print.list pp_op)
    (QCheck.Gen.list_size (QCheck.Gen.int_bound 200) gen_op)

let model_size = Int_map.cardinal

let apply (set, model) = function
  | Add (idx, v) ->
      Sparse_set.add set (entity_of_index idx) v;
      (set, Int_map.add idx v model)
  | Set_value (idx, v) ->
      Sparse_set.set_value set (entity_of_index idx) v;
      (set, Int_map.add idx v model)
  | Remove idx ->
      Sparse_set.remove set (entity_of_index idx);
      (set, Int_map.remove idx model)

let iter_pairs set =
  let acc = ref [] in
  Sparse_set.iter (fun idx v -> acc := (idx, v) :: !acc) set;
  !acc

let prop_sparse_set_membership_invariants =
  let test_fn ops =
    let set = Sparse_set.create ~capacity:4 () in
    let _, model =
      List.fold_left apply (set, Int_map.empty) ops
    in
    let size_ok = Sparse_set.size set = model_size model in
    let membership_ok =
      Int_map.for_all
        (fun idx expected ->
          let entity = entity_of_index idx in
          Sparse_set.contains set entity
          && Sparse_set.get set entity = Some expected)
        model
    in
    let iter_items = iter_pairs set in
    let iter_count_ok = List.length iter_items = Sparse_set.size set in
    let iter_ok =
      List.for_all
        (fun (idx, value) -> Int_map.find_opt idx model = Some value)
        iter_items
    in
    let absent_ok =
      let rec loop idx =
        if idx > max_entity_index then true
        else
          let in_model = Int_map.mem idx model in
          let in_set = Sparse_set.contains set (entity_of_index idx) in
          if in_model = in_set then loop (idx + 1) else false
      in
      loop 0
    in
    size_ok && membership_ok && iter_count_ok && iter_ok && absent_ok
  in
  QCheck.Test.make
    ~name:"Sparse_set model membership invariants"
    ~count:1_000
    arb_ops
    test_fn

let tests =
  [ QCheck_alcotest.to_alcotest prop_sparse_set_membership_invariants ]

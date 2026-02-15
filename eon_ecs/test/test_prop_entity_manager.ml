module Entity_manager = Eon_ecs__Entity_manager
module Entity_id = Eon_ecs__Entity_id

module Int_map = Map.Make (Int)

type op =
  | Create
  | Destroy of int

let pp_op = function
  | Create -> "create"
  | Destroy selector -> Printf.sprintf "destroy(%d)" selector

let gen_op =
  let open QCheck.Gen in
  frequency
    [
      (6, pure Create);
      (4, map (fun i -> Destroy i) (int_bound 255));
    ]

let arb_ops =
  QCheck.make
    ~print:(QCheck.Print.list pp_op)
    (QCheck.Gen.list_size (QCheck.Gen.int_bound 300) gen_op)

let pick_nth bindings n =
  let len = List.length bindings in
  if len = 0 then None
  else Some (List.nth bindings (n mod len))

let is_expected_alive alive id =
  let idx = Entity_id.index id in
  let gen = Entity_id.generation id in
  Int_map.find_opt idx alive = Some gen

let check_invariants mgr alive history =
  let count_ok = Entity_manager.count mgr = Int_map.cardinal alive in
  let alive_entries_ok =
    Int_map.for_all
      (fun idx gen -> Entity_manager.is_alive mgr (Entity_id.make idx gen))
      alive
  in
  let history_ok =
    List.for_all
      (fun id -> Entity_manager.is_alive mgr id = is_expected_alive alive id)
      history
  in
  count_ok && alive_entries_ok && history_ok

let step (mgr, alive, history) = function
  | Create ->
      let id = Entity_manager.create_entity mgr in
      let idx = Entity_id.index id in
      let gen = Entity_id.generation id in
      (mgr, Int_map.add idx gen alive, id :: history)
  | Destroy selector ->
      begin
        match pick_nth (Int_map.bindings alive) selector with
        | None -> (mgr, alive, history)
        | Some (idx, gen) ->
            Entity_manager.destroy_entity mgr (Entity_id.make idx gen);
            (mgr, Int_map.remove idx alive, history)
      end

let prop_entity_manager_generational_safety =
  let test_fn ops =
    let mgr = Entity_manager.create 4 in
    let _, alive, history = List.fold_left step (mgr, Int_map.empty, []) ops in
    check_invariants mgr alive history
  in
  QCheck.Test.make
    ~name:"Entity_manager generational safety"
    ~count:1_000
    arb_ops
    test_fn

let tests =
  [ QCheck_alcotest.to_alcotest prop_entity_manager_generational_safety ]

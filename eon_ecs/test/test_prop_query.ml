module World = Eon_ecs__World
module Query = Eon_ecs__Query

(* Every entity independently has each component with a random probability,
   so which component ends up smallest (and hence the iteration base) varies
   across runs without any special-casing — the property must hold no matter
   which slot happens to be smallest. *)
let build_world ~entity_count ~component_names ~membership =
  let world = World.create () in
  List.iteri (fun id name -> ignore (World.register_component world ~name ~id)) component_names;
  let entities = Array.init entity_count (fun _ -> World.create_entity world) in
  Array.iteri
    (fun eidx entity ->
      List.iteri
        (fun cidx name ->
          if membership.(eidx).(cidx) then
            World.add_component world entity ~name (eidx, cidx))
        component_names)
    entities;
  (world, entities)

let gen_membership ~entity_count ~component_count =
  let open QCheck.Gen in
  array_size (return entity_count) (array_size (return component_count) bool)

let gen_world ~component_count =
  let open QCheck.Gen in
  let* entity_count = int_range 0 60 in
  let* membership = gen_membership ~entity_count ~component_count in
  return (entity_count, membership)

let pp_world (entity_count, _) = Printf.sprintf "entity_count=%d" entity_count

let arb_world ~component_count = QCheck.make ~print:pp_world (gen_world ~component_count)

let has_all membership eidx component_indices =
  List.for_all (fun cidx -> membership.(eidx).(cidx)) component_indices

let entity_index entities e =
  let n = Array.length entities in
  let rec go i = if i >= n then None else if entities.(i) = e then Some i else go (i + 1) in
  go 0

(* ------------------------------------------------------------------ *)
(* iter1                                                               *)
(* ------------------------------------------------------------------ *)

let prop_iter1_matches_membership =
  let test_fn (entity_count, membership) =
    let world, entities = build_world ~entity_count ~component_names:[ "C0" ] ~membership in
    let seen = ref [] in
    Query.iter1 world "C0" (fun e (eidx, cidx) -> seen := (e, eidx, cidx) :: !seen);
    let expected_count =
      let c = ref 0 in
      Array.iter (fun row -> if row.(0) then incr c) membership;
      !c
    in
    List.length !seen = expected_count
    && List.for_all
         (fun (e, eidx, cidx) ->
           match entity_index entities e with
           | Some i -> i = eidx && cidx = 0 && membership.(i).(0)
           | None -> false)
         !seen
  in
  QCheck.Test.make ~name:"Query.iter1 visits exactly the entities holding the component"
    ~count:500 (arb_world ~component_count:1) test_fn

(* ------------------------------------------------------------------ *)
(* iter2 / iter3 / iter4 — intersection correctness, order-independent  *)
(* of which component happens to have the fewest members.               *)
(* ------------------------------------------------------------------ *)

let check_intersection ~arity ~run_iter =
  let component_names = List.init arity (fun i -> Printf.sprintf "C%d" i) in
  let component_indices = List.init arity (fun i -> i) in
  let test_fn (entity_count, membership) =
    let world, entities = build_world ~entity_count ~component_names ~membership in
    let visited = ref [] in
    run_iter world entities (fun e -> visited := e :: !visited);
    let expected =
      List.filteri (fun eidx _ -> has_all membership eidx component_indices)
        (Array.to_list entities)
    in
    let count = Query.count world component_names in
    List.length !visited = List.length expected
    && List.sort compare !visited = List.sort compare expected
    && count = List.length expected
  in
  QCheck.Test.make
    ~name:(Printf.sprintf "Query.iter%d visits exactly the intersection, count agrees" arity)
    ~count:500 (arb_world ~component_count:arity) test_fn

let prop_iter2 =
  check_intersection ~arity:2 ~run_iter:(fun world entities f ->
      ignore entities;
      Query.iter2 world "C0" "C1" (fun e _ _ -> f e))

let prop_iter3 =
  check_intersection ~arity:3 ~run_iter:(fun world entities f ->
      ignore entities;
      Query.iter3 world "C0" "C1" "C2" (fun e _ _ _ -> f e))

let prop_iter4 =
  check_intersection ~arity:4 ~run_iter:(fun world entities f ->
      ignore entities;
      Query.iter4 world "C0" "C1" "C2" "C3" (fun e _ _ _ _ -> f e))

(* ------------------------------------------------------------------ *)
(* count / iter_entities agree regardless of the number/order of names. *)
(* ------------------------------------------------------------------ *)

let prop_count_matches_iter_entities =
  let arity = 3 in
  let component_names = List.init arity (fun i -> Printf.sprintf "C%d" i) in
  let test_fn (entity_count, membership) =
    let world, _ = build_world ~entity_count ~component_names ~membership in
    let via_iter_entities =
      let acc = ref 0 in
      Query.iter_entities world component_names (fun _ -> incr acc);
      !acc
    in
    let via_count = Query.count world component_names in
    let via_reversed_names = Query.count world (List.rev component_names) in
    via_iter_entities = via_count && via_count = via_reversed_names
  in
  QCheck.Test.make
    ~name:"Query.count agrees with iter_entities and is independent of name order"
    ~count:500 (arb_world ~component_count:arity) test_fn

let tests =
  [
    QCheck_alcotest.to_alcotest prop_iter1_matches_membership;
    QCheck_alcotest.to_alcotest prop_iter2;
    QCheck_alcotest.to_alcotest prop_iter3;
    QCheck_alcotest.to_alcotest prop_iter4;
    QCheck_alcotest.to_alcotest prop_count_matches_iter_entities;
  ]

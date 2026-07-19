module Component_registry = Eon_ecs__Component_registry
module Component = Eon_ecs__Component

let gen_names =
  let open QCheck.Gen in
  let* n = int_range 0 30 in
  let indices = List.init n (fun i -> i) in
  let* shuffled = shuffle_list indices in
  return (List.map (fun i -> (Printf.sprintf "C%d" i, i)) shuffled)

let pp_names names = Printf.sprintf "n=%d" (List.length names)

let arb_names = QCheck.make ~print:pp_names gen_names

let prop_register_find_count_round_trip =
  let test_fn names_with_ids =
    let reg = Component_registry.create () in
    List.iter (fun (name, id) -> ignore (Component_registry.register reg ~name ~id)) names_with_ids;
    let count_ok = Component_registry.count reg = List.length names_with_ids in
    let find_ok =
      List.for_all
        (fun (name, id) ->
          match Component_registry.find reg ~name with
          | Some (c : int Component.component) -> c.Component.id = id && c.Component.name = name
          | None -> false)
        names_with_ids
    in
    let iter_visits_every_name =
      let visited = ref [] in
      Component_registry.iter
        (fun (Component.Component c) -> visited := c.Component.name :: !visited)
        reg;
      List.length !visited = List.length names_with_ids
      && List.sort compare !visited = List.sort compare (List.map fst names_with_ids)
    in
    count_ok && find_ok && iter_visits_every_name
  in
  QCheck.Test.make
    ~name:"Component_registry: registering a set of distinct names round-trips through find/count/iter"
    ~count:500 arb_names test_fn

let prop_find_missing_is_none =
  let test_fn names_with_ids =
    let reg = Component_registry.create () in
    List.iter (fun (name, id) -> ignore (Component_registry.register reg ~name ~id)) names_with_ids;
    (Component_registry.find reg ~name:"definitely-not-registered" : int Component.component option)
    = None
  in
  QCheck.Test.make ~name:"Component_registry: an unregistered name is always absent"
    ~count:200 arb_names test_fn

let prop_duplicate_register_raises =
  let test_fn names_with_ids =
    match names_with_ids with
    | [] -> true (* nothing to duplicate *)
    | (name, id) :: _ ->
        let reg = Component_registry.create () in
        List.iter (fun (n, i) -> ignore (Component_registry.register reg ~name:n ~id:i)) names_with_ids;
        (match Component_registry.register reg ~name ~id:(id + 1) with
        | (_ : int Component.component) -> false
        | exception Failure msg -> msg = "Component already registered: " ^ name)
  in
  QCheck.Test.make ~name:"Component_registry: re-registering an existing name always raises"
    ~count:200 arb_names test_fn

let tests =
  [
    QCheck_alcotest.to_alcotest prop_register_find_count_round_trip;
    QCheck_alcotest.to_alcotest prop_find_missing_is_none;
    QCheck_alcotest.to_alcotest prop_duplicate_register_raises;
  ]

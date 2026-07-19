module G = Eon_ecs__Dependency_graph

(* ------------------------------------------------------------------ *)
(* Property 1: random acyclic edge sets are always sorted correctly.   *)
(* ------------------------------------------------------------------ *)

(* Edges only ever go from a smaller int to a larger one, so the edge set
   is acyclic by construction regardless of which pairs are picked. *)
let gen_acyclic_graph =
  let open QCheck.Gen in
  let* n = int_range 1 15 in
  let candidate_pairs =
    List.concat_map
      (fun i -> List.init (n - i - 1) (fun k -> (i, i + 1 + k)))
      (List.init n (fun i -> i))
  in
  let* edges =
    list_size (return (List.length candidate_pairs)) bool
    >|= fun flags -> List.filteri (fun idx _ -> List.nth flags idx) candidate_pairs
  in
  return (n, edges)

let pp_graph (n, edges) =
  Printf.sprintf "n=%d edges=%s" n
    (String.concat ";" (List.map (fun (a, b) -> Printf.sprintf "(%d,%d)" a b) edges))

let arb_acyclic_graph = QCheck.make ~print:pp_graph gen_acyclic_graph

let build_graph n edges =
  let g = List.fold_left (fun g i -> G.add_node i g) (G.create ()) (List.init n (fun i -> i)) in
  List.fold_left (fun g (a, b) -> G.before ~earlier:a ~later:b g) g edges

let position order node =
  let rec go i = function
    | [] -> None
    | x :: _ when x = node -> Some i
    | _ :: tl -> go (i + 1) tl
  in
  go 0 order

let prop_topo_sort_respects_before_constraints =
  let test_fn (n, edges) =
    let g = build_graph n edges in
    let order = G.topo_sort g in
    let all_nodes_present =
      List.length order = n
      && List.sort compare order = List.sort compare (List.init n (fun i -> i))
    in
    let constraints_respected =
      List.for_all
        (fun (earlier, later) ->
          match position order earlier, position order later with
          | Some pe, Some pl -> pe < pl
          | _ -> false)
        edges
    in
    all_nodes_present && constraints_respected
  in
  QCheck.Test.make
    ~name:"Dependency_graph topo_sort respects all before constraints (random acyclic edges)"
    ~count:1_000
    arb_acyclic_graph
    test_fn

(* ------------------------------------------------------------------ *)
(* Property 2: any edge set forming a full cycle always raises.        *)
(* ------------------------------------------------------------------ *)

let gen_cyclic_graph = QCheck.Gen.int_range 2 15

let arb_cyclic_graph = QCheck.make ~print:string_of_int gen_cyclic_graph

let build_cycle n =
  let g = List.fold_left (fun g i -> G.add_node i g) (G.create ()) (List.init n (fun i -> i)) in
  let g =
    List.fold_left
      (fun g i -> G.before ~earlier:i ~later:(i + 1) g)
      g
      (List.init (n - 1) (fun i -> i))
  in
  (* Close the loop: last node back to the first. *)
  G.before ~earlier:(n - 1) ~later:0 g

let prop_topo_sort_raises_on_cycle =
  let test_fn n =
    let g = build_cycle n in
    match G.topo_sort g with
    | (_ : int list) -> false
    | exception Invalid_argument _ -> true
  in
  QCheck.Test.make
    ~name:"Dependency_graph topo_sort raises on any full-cycle edge set"
    ~count:100
    arb_cyclic_graph
    test_fn

let tests =
  [
    QCheck_alcotest.to_alcotest prop_topo_sort_respects_before_constraints;
    QCheck_alcotest.to_alcotest prop_topo_sort_raises_on_cycle;
  ]

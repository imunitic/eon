open Alcotest
module G = Eon_ecs.Dependency_graph

let test_empty () =
  let order = G.create () |> G.topo_sort in
  check (list string) "empty" [] order

let test_single_node () =
  let order = G.create () |> G.add_node "A" |> G.topo_sort in
  check (list string) "singleton" ["A"] order

let test_linear_chain () =
  let g =
    G.create ()
    |> G.add_node "A"
    |> G.add_node "B"
    |> G.add_node "C"
    |> G.before ~earlier:"A" ~later:"B"
    |> G.before ~earlier:"B" ~later:"C"
  in
  check (list string) "linear" ["A"; "B"; "C"] (G.topo_sort g)

(* A -> B, A -> C, B -> D, C -> D *)
let test_diamond () =
  let g =
    G.create ()
    |> G.add_node "A"
    |> G.add_node "B"
    |> G.add_node "C"
    |> G.add_node "D"
    |> G.before ~earlier:"A" ~later:"B"
    |> G.before ~earlier:"A" ~later:"C"
    |> G.before ~earlier:"B" ~later:"D"
    |> G.before ~earlier:"C" ~later:"D"
  in
  let order = G.topo_sort g in
  let pos n =
    let rec go i = function
      | [] -> failwith "not found"
      | x :: _ when x = n -> i
      | _ :: tl -> go (i + 1) tl
    in go 0 order
  in
  check bool "A before B" true (pos "A" < pos "B");
  check bool "A before C" true (pos "A" < pos "C");
  check bool "B before D" true (pos "B" < pos "D");
  check bool "C before D" true (pos "C" < pos "D")

let test_cycle () =
  let g =
    G.create ()
    |> G.add_node "A"
    |> G.add_node "B"
    |> G.before ~earlier:"A" ~later:"B"
    |> G.before ~earlier:"B" ~later:"A"
  in
  check_raises "cycle" (Invalid_argument "Dependency_graph: cycle detected")
    (fun () -> ignore (G.topo_sort g))

let test_cache_invalidation () =
  let g = G.create () |> G.add_node "A" |> G.add_node "B" in
  ignore (G.topo_sort g);
  check bool "clean after sort" true (G.is_clean g);
  let g2 = G.before ~earlier:"A" ~later:"B" g in
  check bool "dirty after new edge" false (G.is_clean g2);
  let order2 = G.topo_sort g2 in
  check bool "clean after re-sort" true (G.is_clean g2);
  check (list string) "correct after re-sort" ["A"; "B"] order2

let tests =
  [
    test_case "empty graph"        `Quick test_empty;
    test_case "single node"        `Quick test_single_node;
    test_case "linear chain"       `Quick test_linear_chain;
    test_case "diamond DAG"        `Quick test_diamond;
    test_case "cycle raises"       `Quick test_cycle;
    test_case "cache invalidation" `Quick test_cache_invalidation;
  ]

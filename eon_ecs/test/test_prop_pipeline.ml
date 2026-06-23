module Single_bus = Eon_ecs__Single_bus
module Double_bus = Eon_ecs__Double_bus
module System = Eon_ecs__System
module Sys = System.Make (Single_bus) (Double_bus) (Single_bus)
module Buses_impl = Eon_ecs__Buses.Make (Single_bus) (Double_bus) (Single_bus)
module Pipeline_impl = Eon_ecs__Pipeline.Make (Sys) (Buses_impl)

type graph_case = {
  node_count : int;
  edges : (int * int) list;
}

let pp_edge (a, b) = Printf.sprintf "%d->%d" a b

let pp_graph_case g =
  let edges_s = String.concat "; " (List.map pp_edge g.edges) in
  Printf.sprintf "{nodes=%d; edges=[%s]}" g.node_count edges_s

let normalize_edges node_count edges =
  let tbl = Hashtbl.create 64 in
  List.iter
    (fun (a, b) ->
      if a >= 0 && a < node_count && b >= 0 && b < node_count then
        Hashtbl.replace tbl (a, b) ())
    edges;
  Hashtbl.to_seq_keys tbl |> List.of_seq

let gen_graph_case =
  let open QCheck.Gen in
  let gen_node_count = int_range 1 6 in
  let gen_edge = map2 (fun a b -> (a, b)) (int_bound 5) (int_bound 5) in
  map2
    (fun node_count raw_edges ->
      { node_count; edges = normalize_edges node_count raw_edges })
    gen_node_count
    (list_size (int_bound 20) gen_edge)

let arb_graph_case =
  QCheck.make
    ~print:pp_graph_case
    gen_graph_case

let has_cycle node_count edges =
  let adj = Array.make node_count [] in
  List.iter (fun (a, b) -> adj.(a) <- b :: adj.(a)) edges;
  let color = Array.make node_count 0 in
  let rec dfs v =
    color.(v) <- 1;
    let rec visit = function
      | [] ->
          color.(v) <- 2;
          false
      | n :: tl ->
          if color.(n) = 1 then true
          else if color.(n) = 0 && dfs n then true
          else visit tl
    in
    visit adj.(v)
  in
  let rec loop v =
    if v >= node_count then false
    else if color.(v) <> 0 then loop (v + 1)
    else if dfs v then true
    else loop (v + 1)
  in
  loop 0

let check_topological_order node_count edges order =
  let n = List.length order in
  if n <> node_count then false
  else
    let pos = Array.make node_count (-1) in
    let rec fill i = function
      | [] -> true
      | v :: tl ->
          if v < 0 || v >= node_count || pos.(v) <> -1 then false
          else (
            pos.(v) <- i;
            fill (i + 1) tl
          )
    in
    fill 0 order
    && List.for_all (fun (a, b) -> pos.(a) < pos.(b)) edges

let prop_pipeline_topo_sort_ordering =
  let test_fn g =
    let p =
      List.init g.node_count Fun.id
      |> List.fold_left (fun acc phase -> Pipeline_impl.add_phase phase acc) (Pipeline_impl.create ())
      |> fun pipe ->
      List.fold_left
        (fun acc (a, b) -> Pipeline_impl.before ~earlier:a ~later:b acc)
        pipe
        g.edges
    in
    if has_cycle g.node_count g.edges then
      (try
         ignore (Pipeline_impl.phases p);
         false
       with Invalid_argument _ -> true)
    else
      let order = Pipeline_impl.phases p in
      check_topological_order g.node_count g.edges order
  in
  QCheck.Test.make
    ~name:"Pipeline topo_sort ordering and cycle detection"
    ~count:1_000
    arb_graph_case
    test_fn

let tests =
  [ QCheck_alcotest.to_alcotest prop_pipeline_topo_sort_ordering ]

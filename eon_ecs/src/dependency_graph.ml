type 'node t = {
  nodes : 'node list;
  edges : ('node * 'node) list;
  cache : 'node list option ref;
}

let create () = { nodes = []; edges = []; cache = ref None }

let add_node node t =
  if List.mem node t.nodes then t
  else { nodes = node :: t.nodes; edges = t.edges; cache = ref None }

let ensure_node node t =
  if List.mem node t.nodes then t
  else { t with nodes = node :: t.nodes; cache = ref None }

let before ~earlier ~later t =
  let t = t |> ensure_node earlier |> ensure_node later in
  if List.exists (fun (a, b) -> a = earlier && b = later) t.edges then t
  else { t with edges = (earlier, later) :: t.edges; cache = ref None }

let after ~later ~earlier t = before ~earlier ~later t

let topo_sort t =
  match !(t.cache) with
  | Some order -> order
  | None ->
    let n = List.length t.nodes in
    let incoming = Hashtbl.create n
    and outgoing = Hashtbl.create n in
    List.iter (fun p ->
      Hashtbl.replace incoming p 0;
      Hashtbl.replace outgoing p []) t.nodes;
    List.iter (fun (a, b) ->
      Hashtbl.replace outgoing a (b :: Hashtbl.find outgoing a);
      Hashtbl.replace incoming b (Hashtbl.find incoming b + 1))
      t.edges;
    let queue =
      Hashtbl.fold (fun p deg acc -> if deg = 0 then p :: acc else acc) incoming []
    in
    let rec visit acc = function
      | [] -> List.rev acc
      | p :: rest ->
        let next =
          List.fold_left
            (fun acc node ->
              let deg = Hashtbl.find incoming node - 1 in
              Hashtbl.replace incoming node deg;
              if deg = 0 then node :: acc else acc)
            rest
            (Hashtbl.find outgoing p)
        in
        visit (p :: acc) next
    in
    let order = visit [] queue in
    if List.length order < n then
      invalid_arg "Dependency_graph: cycle detected";
    t.cache := Some order;
    order

let is_clean t = Option.is_some !(t.cache)

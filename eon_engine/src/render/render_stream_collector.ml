type 'command collector = World.ro World.t -> 'command Render_stream.t -> unit

type ('phase, 'command) t = {
  phases     : ('phase, unit) Hashtbl.t;
  mutable graph      : 'phase Eon_ecs.Dependency_graph.t;
  collectors : ('phase, 'command collector list) Hashtbl.t;
}

let create () = {
  phases     = Hashtbl.create 8;
  graph      = Eon_ecs.Dependency_graph.create ();
  collectors = Hashtbl.create 8;
}

let add_phase ?after phase t =
  (match after with
   | Some a when not (Hashtbl.mem t.phases a) ->
     invalid_arg "Render_stream_collector.add_phase: ~after phase not registered"
   | _ -> ());
  if not (Hashtbl.mem t.phases phase) then begin
    Hashtbl.add t.phases phase ();
    t.graph <- Eon_ecs.Dependency_graph.add_node phase t.graph
  end;
  (match after with
   | Some a -> t.graph <- Eon_ecs.Dependency_graph.before ~earlier:a ~later:phase t.graph
   | None   -> ());
  t

let add_collector phase collector t =
  if not (Hashtbl.mem t.phases phase) then
    invalid_arg "Render_stream_collector.add_collector: phase not registered";
  let existing = Hashtbl.find_opt t.collectors phase |> Option.value ~default:[] in
  Hashtbl.replace t.collectors phase (existing @ [collector]);
  t

let collect t world stream =
  List.iter
    (fun phase ->
       match Hashtbl.find_opt t.collectors phase with
       | None      -> ()
       | Some cols -> List.iter (fun c -> c world stream) cols)
    (Eon_ecs.Dependency_graph.topo_sort t.graph)

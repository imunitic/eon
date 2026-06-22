module type S = sig
  type 'phase t
  type ('s, 'e, 'c) system_t
  type kind
  type world

  val create       : unit -> 'phase t
  val add_phase    : 'phase -> 'phase t -> 'phase t
  val before       : earlier:'phase -> later:'phase -> 'phase t -> 'phase t
  val after        : later:'phase  -> earlier:'phase -> 'phase t -> 'phase t
  val add_system   : 'phase -> ('s, 'e, 'c) system_t -> 'phase t -> 'phase t
  val register_all : 'phase t -> world -> unit
  val run          : 'phase t -> world -> float -> world
  val run_by_filter :
    filter:(kind -> bool) ->
    'phase t -> world -> float -> world
  val phases       : 'phase t -> 'phase list
end

module Make
    (System   : System.DISPATCH)
    (Executor : Executor.S)
  : S with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
       and type kind = System.kind
       and type world = World.rw World.t
= struct
  type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
  type kind = System.kind
  type world = World.rw World.t

  (* Existential wrapper hiding the signal/event/command type parameters. *)
  type entry = Entry : ('s, 'e, 'c) System.t -> entry

  type 'phase t = {
    phases  : ('phase, unit) Hashtbl.t;
    mutable graph   : 'phase Eon_ecs.Dependency_graph.t;
    systems : ('phase, entry list) Hashtbl.t;
  }

  let create () =
    { phases  = Hashtbl.create 16;
      graph   = Eon_ecs.Dependency_graph.create ();
      systems = Hashtbl.create 16 }

  let add_phase phase t =
    if not (Hashtbl.mem t.phases phase) then begin
      Hashtbl.add t.phases phase ();
      t.graph <- Eon_ecs.Dependency_graph.add_node phase t.graph
    end;
    t

  let before ~earlier ~later t =
    t.graph <- Eon_ecs.Dependency_graph.before ~earlier ~later t.graph;
    t

  let after ~later ~earlier t = before ~earlier ~later t

  let add_system phase (sys : ('s, 'e, 'c) system_t) t =
    if not (Hashtbl.mem t.phases phase) then
      invalid_arg "Pipeline.add_system: phase not registered";
    let lst = Hashtbl.find_opt t.systems phase |> Option.value ~default:[] in
    Hashtbl.replace t.systems phase (Entry sys :: lst);
    t

  let sorted_phases t = Eon_ecs.Dependency_graph.topo_sort t.graph

  let register_all t world =
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some entries ->
          List.iter
            (fun (Entry s) -> System.attach s world)
            (List.rev entries))
      (sorted_phases t)

  (* Builds parallel job list and exclusive dispatch list for one phase.
     Parallel systems run via Executor with ro World.t; exclusive systems run
     sequentially after Executor.run_all returns, with rw World.t. *)
  let dispatch_phase entries ro rw dt =
    let revd = List.rev entries in
    let parallel_jobs = List.filter_map
      (fun (Entry s) ->
        if System.is_parallel s
        then Some (fun () -> System.update_ro s ro dt)
        else None)
      revd
    in
    Executor.run_all parallel_jobs;
    List.iter
      (fun (Entry s) ->
        if not (System.is_parallel s)
        then System.update_rw s rw dt)
      revd

  let dispatch_phase_filtered ~filter entries ro rw dt =
    let revd = List.rev entries in
    let parallel_jobs = List.filter_map
      (fun (Entry s) ->
        if System.is_parallel s && filter (System.kind_of s)
        then Some (fun () -> System.update_ro s ro dt)
        else None)
      revd
    in
    Executor.run_all parallel_jobs;
    List.iter
      (fun (Entry s) ->
        if not (System.is_parallel s) && filter (System.kind_of s)
        then System.update_rw s rw dt)
      revd

  let run t world dt =
    let ro = World.readonly world in
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some entries -> dispatch_phase entries ro world dt)
      (sorted_phases t);
    world

  let run_by_filter ~filter t world dt =
    let ro = World.readonly world in
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some entries -> dispatch_phase_filtered ~filter entries ro world dt)
      (sorted_phases t);
    world

  let phases t = sorted_phases t
end


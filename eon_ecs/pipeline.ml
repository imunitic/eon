(* ================================================================ *)
(* 🔹 Pipeline Interface                                             *)
(* ================================================================ *)

module type S = sig
  (** Pipeline state keyed by phase values. *)
  type 'phase t
  (** System type stored in this pipeline implementation. *)
  type ('s, 'e, 'c) system_t
  (** Kind tag used for filtered execution. *)
  type kind

  (** Create an empty pipeline. *)
  val create : unit -> 'phase t
  (** Add a phase if not already present. *)
  val add_phase : 'phase -> 'phase t -> 'phase t
  (** Declare [earlier] must run before [later]. *)
  val before : earlier:'phase -> later:'phase -> 'phase t -> 'phase t
  (** Declare [later] must run after [earlier]. *)
  val after  : later:'phase -> earlier:'phase -> 'phase t -> 'phase t

  (** Attach a system to a phase.

      Raises [Invalid_argument] if the phase is not registered.
  *)
  val add_system : 'phase -> ('s, 'e, 'c) system_t -> 'phase t -> 'phase t

  (** World type this pipeline operates on. *)
  type world
  (** Run [register] for every system then attach bus handlers, in phase order.
      Bus instances come from the [Buses] argument to [Make]. *)
  val register_all : 'phase t -> world -> unit
  (** Run systems filtered by a predicate on their kind.
      Used internally by the Progress module. *)
  val run_by_filter :
    filter:(kind -> bool) ->
    'phase t -> world -> float -> world
  (** Run all systems in topological phase order. *)
  val run : 'phase t -> world -> float -> world
  (** Return phases in resolved topological order. *)
  val phases : 'phase t -> 'phase list
end

(* ================================================================ *)
(* 🔹 Pipeline Implementation (Functor)                              *)
(* ================================================================ *)

module Make
    (System : System.S)
    (Buses : sig
      val signals  : unit -> 'a System.Signal_bus.t
      val events   : unit -> 'a System.Event_bus.t
      val commands : unit -> 'a System.Command_bus.t
    end) = struct
  type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
  type kind = System.kind
  type world = World.t

  type entry = Entry : ('s, 'e, 'c) System.t -> entry

  type 'phase t = {
      phases  : ('phase, unit) Hashtbl.t;
      mutable graph   : 'phase Dependency_graph.t;
      systems : ('phase, entry list) Hashtbl.t;
    }

  let create () =
    { phases = Hashtbl.create 16;
      graph = Dependency_graph.create ();
      systems = Hashtbl.create 16 }

  let add_phase phase t =
    if not (Hashtbl.mem t.phases phase) then begin
      Hashtbl.add t.phases phase ();
      t.graph <- Dependency_graph.add_node phase t.graph
    end;
    t

  let before ~earlier ~later t =
    t.graph <- Dependency_graph.before ~earlier ~later t.graph;
    t

  let after ~later ~earlier t = before ~earlier ~later t

  let add_system phase (sys : ('s, 'e, 'c) system_t) t =
    if not (Hashtbl.mem t.phases phase) then
      invalid_arg "Pipeline.add_system: phase not registered";
    let lst = Hashtbl.find_opt t.systems phase |> Option.value ~default:[] in
    Hashtbl.replace t.systems phase (Entry sys :: lst);
    t

  let sorted_phases t = Dependency_graph.topo_sort t.graph

  let register_all t world =
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some entries ->
          List.iter
            (fun (Entry sys) ->
              System.register sys world;
              System.attach sys world
                ~signals:(Buses.signals ())
                ~events:(Buses.events ())
                ~commands:(Buses.commands ()))
            (List.rev entries))
      (sorted_phases t)

  let run t world dt =
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some entries ->
          List.iter
            (fun (Entry sys) -> System.run sys world dt)
            (List.rev entries))
      (sorted_phases t);
    world

  let run_by_filter ~filter t world dt =
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some entries ->
          List.iter
            (fun (Entry sys) ->
              if filter (System.kind_of sys) then System.run sys world dt)
            (List.rev entries))
      (sorted_phases t);
    world

  let phases t = sorted_phases t
end

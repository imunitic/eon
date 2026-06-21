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

  (** Execute [register] callback of every system in phase order. *)
  val register_all : 'phase t -> World.t -> unit
(** Run systems filtered by a predicate on their kind.
    This is used internally by the Progress module. *)
val run_by_filter :
  filter:(kind -> bool) ->
  'phase t -> World.t -> float -> World.t

  (** Run all systems in topological phase order. *)
  val run : 'phase t -> World.t -> float -> World.t
  (** Return phases in resolved topological order. *)
  val phases : 'phase t -> 'phase list
end

(* ================================================================ *)
(* 🔹 Pipeline Implementation (Functor)                              *)
(* ================================================================ *)

module Make (System : System.S) = struct
  type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
  type kind = System.kind

  type system_entry = {
      kind : System.kind;
      core : System.core;
    }

  (* ================================================================ *)
  (* 🔹 Types *)
  (* ================================================================ *)

  type 'phase t = {
      phases  : ('phase, unit) Hashtbl.t;
      mutable graph   : 'phase Dependency_graph.t;
      systems : ('phase, system_entry list) Hashtbl.t;
    }

  (* ================================================================ *)
  (* 🔹 Construction *)
  (* ================================================================ *)

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

  (* ================================================================ *)
  (* 🔹 Ordering management *)
  (* ================================================================ *)

  let before ~earlier ~later t =
    t.graph <- Dependency_graph.before ~earlier ~later t.graph;
    t

  let after ~later ~earlier t = before ~earlier ~later t

  (* ================================================================ *)
  (* 🔹 System registration *)
  (* ================================================================ *)

  let add_system phase (sys : ('s, 'e, 'c) system_t) t =
    if not (Hashtbl.mem t.phases phase) then
      invalid_arg "Pipeline.add_system: phase not registered";
    let lst = Hashtbl.find_opt t.systems phase |> Option.value ~default:[] in
    let entry = { kind = sys.kind; core = sys.core } in
    Hashtbl.replace t.systems phase (entry :: lst);
    t

  (* ================================================================ *)
  (* 🔹 Phase sorting *)
  (* ================================================================ *)

  let sorted_phases t = Dependency_graph.topo_sort t.graph

  (* ================================================================ *)
  (* 🔹 Execution helpers *)
  (* ================================================================ *)

  let register_all t world =
    let order = sorted_phases t in
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some systems ->
           List.iter (fun s -> s.core.register world) (List.rev systems))
      order

  let run_by_filter ~filter t world dt =
    let order = sorted_phases t in
    List.fold_left
      (fun world phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> world
        | Some systems ->
           List.fold_left
             (fun w (s : system_entry) ->
               if filter s.kind then (
                 s.core.update w dt;
                 w
               ) else w)
             world
             (List.rev systems))
      world order

  let run t world dt =
    let order = sorted_phases t in
    List.fold_left
      (fun world phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> world
        | Some systems ->
           List.fold_left
             (fun w s ->
               s.core.update w dt;
               w)
             world
             (List.rev systems))
      world
      order

  let phases t = sorted_phases t
end

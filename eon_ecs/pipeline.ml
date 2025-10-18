(* ================================================================ *)
(* 🔹 Pipeline Interface                                             *)
(* ================================================================ *)

module type S = sig
  type 'phase t
  type ('s, 'e, 'c) system_t

  val create : unit -> 'phase t
  val add_phase : 'phase -> 'phase t -> 'phase t
  val before : earlier:'phase -> later:'phase -> 'phase t -> 'phase t
  val after  : later:'phase -> earlier:'phase -> 'phase t -> 'phase t
  val add_system : 'phase -> ('s, 'e, 'c) system_t -> 'phase t -> 'phase t
  val register_all : 'phase t -> World.t -> unit
  val run : 'phase t -> World.t -> float -> World.t
  val phases : 'phase t -> 'phase list
end

(* ================================================================ *)
(* 🔹 Pipeline Implementation (Functor)                              *)
(* ================================================================ *)

module Make (System : System.S) = struct
  type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t

  (* ================================================================ *)
  (* 🔹 Types *)
  (* ================================================================ *)

  type 'phase t = {
    mutable phases  : ('phase, unit) Hashtbl.t;
    mutable edges   : ('phase * 'phase) list;  (* before → after relationships *)
    mutable systems : ('phase, System.core list) Hashtbl.t;
  }

  (* ================================================================ *)
  (* 🔹 Construction *)
  (* ================================================================ *)

  let create () =
    { phases = Hashtbl.create 16; edges = []; systems = Hashtbl.create 16 }

  let add_phase phase t =
    if not (Hashtbl.mem t.phases phase) then
      Hashtbl.add t.phases phase ();
    t

  (* ================================================================ *)
  (* 🔹 Ordering management *)
  (* ================================================================ *)

  let before ~earlier ~later t =
    if not (List.exists (fun (a, b) -> a = earlier && b = later) t.edges)
    then t.edges <- (earlier, later) :: t.edges;
    t

  let after ~later ~earlier t = before ~earlier ~later t

  (* ================================================================ *)
  (* 🔹 System registration *)
  (* ================================================================ *)

  let add_system phase (sys : ('s, 'e, 'c) System.t) t =
    if not (Hashtbl.mem t.phases phase) then
      invalid_arg "Pipeline.add_system: phase not registered";
    let lst = Hashtbl.find_opt t.systems phase |> Option.value ~default:[] in
    Hashtbl.replace t.systems phase (sys.System.core :: lst);
    t

  (* ================================================================ *)
  (* 🔹 Phase sorting and execution *)
  (* ================================================================ *)

  let topo_sort (edges : ('phase * 'phase) list) (phases : ('phase, unit) Hashtbl.t) =
    let incoming = Hashtbl.create (Hashtbl.length phases)
    and outgoing = Hashtbl.create (Hashtbl.length phases) in

    Hashtbl.iter (fun p _ ->
      Hashtbl.replace incoming p 0;
      Hashtbl.replace outgoing p []) phases;

    List.iter
      (fun (a, b) ->
        Hashtbl.replace outgoing a (b :: (Hashtbl.find outgoing a));
        Hashtbl.replace incoming b ((Hashtbl.find incoming b) + 1))
      edges;

    let queue =
      Hashtbl.fold (fun p deg acc -> if deg = 0 then p :: acc else acc) incoming []
    in

    let rec visit acc = function
      | [] -> List.rev acc
      | p :: rest ->
        let next =
          List.fold_left
            (fun acc n ->
              let deg = Hashtbl.find incoming n - 1 in
              Hashtbl.replace incoming n deg;
              if deg = 0 then n :: acc else acc)
            rest
            (Hashtbl.find outgoing p)
        in
        visit (p :: acc) next
    in
    let order = visit [] queue in
    if List.length order < Hashtbl.length phases then
      invalid_arg "Pipeline: cycle detected in phase dependencies";
    order

  (* ================================================================ *)
  (* 🔹 Execution helpers *)
  (* ================================================================ *)

  let register_all t world =
    let order = topo_sort t.edges t.phases in
    List.iter
      (fun phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> ()
        | Some systems ->
          List.iter (fun (s : System.core) -> s.register world) (List.rev systems))
      order

  let run t world dt =
    let order = topo_sort t.edges t.phases in
    List.fold_left
      (fun world phase ->
        match Hashtbl.find_opt t.systems phase with
        | None -> world
        | Some systems ->
          List.fold_left
            (fun w (sys : System.core) ->
              sys.update w dt;
              w)
            world
            (List.rev systems))
      world
      order

  let phases t = topo_sort t.edges t.phases
end

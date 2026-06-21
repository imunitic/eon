type update_kind =
  | Parallel  of (World_cap.ro World_cap.t -> float -> unit)
  | Exclusive of (World_cap.rw World_cap.t -> float -> unit)

module type S = sig
  type ('s, 'e, 'c) t
  type kind

  val make :
    ?on_signal:(World_cap.rw World_cap.t -> 's -> unit) ->
    ?on_event:(World_cap.rw World_cap.t -> 'e -> unit) ->
    ?on_command:(World_cap.rw World_cap.t -> 'c -> unit) ->
    ?kind:kind ->
    update_kind ->
    ('s, 'e, 'c) t
end

module type DISPATCH = sig
  include S
  val kind_of     : ('s, 'e, 'c) t -> kind
  val is_parallel : ('s, 'e, 'c) t -> bool
  val update_ro   : ('s, 'e, 'c) t -> World_cap.ro World_cap.t -> float -> unit
  val update_rw   : ('s, 'e, 'c) t -> World_cap.rw World_cap.t -> float -> unit
  val register    : ('s, 'e, 'c) t -> World.t -> unit
  val attach      : ('s, 'e, 'c) t -> World.t -> unit
end

module Make (Core_system : Eon_ecs.System.S) : DISPATCH
  with type kind = Core_system.kind
= struct
  type kind = Core_system.kind

  (* Borrow the default kind from Core_system without hard-coding `Variable. *)
  let default_kind : kind =
    (Core_system.make_reactive () : (unit, unit, unit) Core_system.reactive).kind

  type ('s, 'e, 'c) t = {
    register    : World.t -> unit;
    update_kind : update_kind;
    kind        : kind;
    on_signal   : World_cap.rw World_cap.t -> 's -> unit;
    on_event    : World_cap.rw World_cap.t -> 'e -> unit;
    on_command  : World_cap.rw World_cap.t -> 'c -> unit;
  }

  let make
      ?(on_signal  = fun _ _ -> ())
      ?(on_event   = fun _ _ -> ())
      ?(on_command = fun _ _ -> ())
      ?(kind = default_kind)
      update_kind
    =
    { register = (fun _ -> ()); update_kind; kind; on_signal; on_event; on_command }

  let kind_of t = t.kind

  let is_parallel t = match t.update_kind with Parallel _ -> true | Exclusive _ -> false

  let update_ro t (ro : World_cap.ro World_cap.t) dt =
    match t.update_kind with
    | Parallel f -> f ro dt
    | Exclusive _ -> ()

  let update_rw t (rw : World_cap.rw World_cap.t) dt =
    match t.update_kind with
    | Exclusive f -> f rw dt
    | Parallel _ -> ()

  let register t world = t.register world

  (* Reads bus instances from world services and registers closures that wrap
     the engine world in a World_cap.rw before calling the user handler. *)
  let attach t world =
    let rw = World_cap.wrap world in
    (match World.get_service world `Signals with
     | None -> ()
     | Some (bus : 's Core_system.Signal_bus.t) ->
       Core_system.Signal_bus.on bus (fun msg -> t.on_signal rw msg));
    (match World.get_service world `Events with
     | None -> ()
     | Some (bus : 'e Core_system.Event_bus.t) ->
       Core_system.Event_bus.on bus (fun msg -> t.on_event rw msg));
    (match World.get_service world `Commands with
     | None -> ()
     | Some (bus : 'c Core_system.Command_bus.t) ->
       Core_system.Command_bus.on bus (fun msg -> t.on_command rw msg))
end

module Default = Make(Eon_ecs.System.Make(Single_bus)(Double_bus)(Single_bus))

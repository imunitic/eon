type update_kind =
  | Parallel  of (World.ro World.t -> float -> unit)
  | Exclusive of (World.rw World.t -> float -> unit)

module type S = sig
  type ('s, 'e, 'c) t
  type kind

  val make :
    ?on_signal:(World.rw World.t -> 's -> unit) ->
    ?on_event:(World.rw World.t -> 'e -> unit) ->
    ?on_command:(World.rw World.t -> 'c -> unit) ->
    ?kind:kind ->
    update_kind ->
    ('s, 'e, 'c) t
end

module type DISPATCH = sig
  include S
  module Signal_bus  : Bus.S
  module Event_bus   : Bus.S
  module Command_bus : Bus.S
  val kind_of     : ('s, 'e, 'c) t -> kind
  val is_parallel : ('s, 'e, 'c) t -> bool
  val update_ro   : ('s, 'e, 'c) t -> World.ro World.t -> float -> unit
  val update_rw   : ('s, 'e, 'c) t -> World.rw World.t -> float -> unit
  val attach      : ('s, 'e, 'c) t -> World.rw World.t
                    -> signals:'s Signal_bus.t
                    -> events:'e Event_bus.t
                    -> commands:'c Command_bus.t -> unit
end

module Make (Core_system : Eon_ecs.System.S) : DISPATCH
  with type kind = Core_system.kind
   and module Signal_bus  = Core_system.Signal_bus
   and module Event_bus   = Core_system.Event_bus
   and module Command_bus = Core_system.Command_bus
= struct
  type kind = Core_system.kind
  module Signal_bus  = Core_system.Signal_bus
  module Event_bus   = Core_system.Event_bus
  module Command_bus = Core_system.Command_bus

  let default_kind : kind = Core_system.variable

  type ('s, 'e, 'c) t = {
    update_kind : update_kind;
    kind        : kind;
    on_signal   : World.rw World.t -> 's -> unit;
    on_event    : World.rw World.t -> 'e -> unit;
    on_command  : World.rw World.t -> 'c -> unit;
  }

  let make
      ?(on_signal  = fun _ _ -> ())
      ?(on_event   = fun _ _ -> ())
      ?(on_command = fun _ _ -> ())
      ?(kind = default_kind)
      update_kind
    =
    { update_kind; kind; on_signal; on_event; on_command }

  let kind_of t = t.kind

  let is_parallel t = match t.update_kind with Parallel _ -> true | Exclusive _ -> false

  let update_ro t (ro : World.ro World.t) dt =
    match t.update_kind with
    | Parallel f -> f ro dt
    | Exclusive _ -> ()

  let update_rw t (rw : World.rw World.t) dt =
    match t.update_kind with
    | Exclusive f -> f rw dt
    | Parallel _ -> ()

  let attach t (world : World.rw World.t) ~signals ~events ~commands =
    Core_system.Signal_bus.on  signals  (fun msg -> t.on_signal  world msg);
    Core_system.Event_bus.on   events   (fun msg -> t.on_event   world msg);
    Core_system.Command_bus.on commands (fun msg -> t.on_command world msg)
end

module Default = Make(Eon_ecs.System.Make(Single_bus)(Double_bus)(Single_bus))

module type Parallel_def = sig
  type signal
  type event
  type command
  val on_signal  : World.rw World.t -> signal  -> unit
  val on_event   : World.rw World.t -> event   -> unit
  val on_command : World.rw World.t -> command -> unit
  val update     : World.ro World.t -> float -> unit
end

module type Exclusive_def = sig
  type signal
  type event
  type command
  val on_signal  : World.rw World.t -> signal  -> unit
  val on_event   : World.rw World.t -> event   -> unit
  val on_command : World.rw World.t -> command -> unit
  val update     : World.rw World.t -> float -> unit
end

module Make_factory (Sys : DISPATCH) = struct
  let make_parallel (type s e c)
      (module S : Parallel_def with type signal  = s
                                and type event    = e
                                and type command  = c) =
    Sys.make
      ~on_signal:S.on_signal
      ~on_event:S.on_event
      ~on_command:S.on_command
      (Parallel S.update)

  let make_exclusive (type s e c)
      (module S : Exclusive_def with type signal  = s
                                  and type event    = e
                                  and type command  = c) =
    Sys.make
      ~on_signal:S.on_signal
      ~on_event:S.on_event
      ~on_command:S.on_command
      (Exclusive S.update)
end

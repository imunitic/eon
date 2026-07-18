module type KIND = sig
  type kind
  val fixed    : kind
  val variable : kind
end

module Base_kind = struct
  type kind = [ `Fixed | `Variable ]
  let fixed    : kind = `Fixed
  let variable : kind = `Variable
end

type base_kind = Base_kind.kind
type kind = base_kind

module type S = sig
  module type BUS = Bus.S
  module Signal_bus  : BUS
  module Event_bus   : BUS
  module Command_bus : BUS

  type kind
  val variable : kind
  val fixed    : kind

  type ('s, 'e, 'c) t

  val make :
    ?register:(World.t -> unit) ->
    ?update:(World.t -> float -> unit) ->
    ?on_signal:(World.t -> 's -> unit) ->
    ?on_event:(World.t -> 'e -> unit) ->
    ?on_command:(World.t -> 'c -> unit) ->
    ?kind:kind ->
    unit -> ('s, 'e, 'c) t

  val kind_of  : ('s, 'e, 'c) t -> kind
  val register : ('s, 'e, 'c) t -> World.t -> unit
  val run      : ('s, 'e, 'c) t -> World.t -> float -> unit

  val attach :
    ('s, 'e, 'c) t -> World.t ->
    signals:'s Signal_bus.t ->
    events:'e Event_bus.t ->
    commands:'c Command_bus.t -> unit
end

module Make_with_kinds
    (Kinds       : KIND)
    (Signal_bus  : Bus.S)
    (Event_bus   : Bus.S)
    (Command_bus : Bus.S)
  : S with type kind = Kinds.kind
       and module Signal_bus  = Signal_bus
       and module Event_bus   = Event_bus
       and module Command_bus = Command_bus
= struct
  module type BUS = Bus.S
  module Signal_bus  = Signal_bus
  module Event_bus   = Event_bus
  module Command_bus = Command_bus

  type kind = Kinds.kind
  let variable = Kinds.variable
  let fixed    = Kinds.fixed

  type ('s, 'e, 'c) t = {
    register   : World.t -> unit;
    update     : World.t -> float -> unit;
    on_signal  : World.t -> 's -> unit;
    on_event   : World.t -> 'e -> unit;
    on_command : World.t -> 'c -> unit;
    kind       : kind;
  }

  let make
      ?(register   = fun _ -> ())
      ?(update     = fun _ _ -> ())
      ?(on_signal  = fun _ _ -> ())
      ?(on_event   = fun _ _ -> ())
      ?(on_command = fun _ _ -> ())
      ?(kind = Kinds.variable)
      () =
    { register; update; on_signal; on_event; on_command; kind }

  let kind_of sys = sys.kind

  let register sys world    = sys.register world
  let run      sys world dt = sys.update world dt

  let attach sys world ~signals ~events ~commands =
    Signal_bus.on  signals  (fun msg -> sys.on_signal  world msg);
    Event_bus.on   events   (fun msg -> sys.on_event   world msg);
    Command_bus.on commands (fun msg -> sys.on_command world msg)
end

module Make
    (Signal_bus  : Bus.S)
    (Event_bus   : Bus.S)
    (Command_bus : Bus.S) =
  Make_with_kinds(Base_kind)(Signal_bus)(Event_bus)(Command_bus)

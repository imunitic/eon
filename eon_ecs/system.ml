module type KIND = sig
  type kind
  val fixed : kind
  val variable : kind
end

module Base_kind = struct
  type kind = [ `Fixed | `Variable ]
  let fixed : kind = `Fixed
  let variable : kind = `Variable
end

type base_kind = Base_kind.kind
type kind = base_kind

module type S = sig
  module type BUS = Bus.BUS
  module Signal_bus : BUS
  module Event_bus : BUS
  module Command_bus : BUS

  type core = {
    register : World.t -> unit;
    update   : World.t -> float -> unit;
  }

  type kind

  type ('signal, 'event, 'command) reactive = {
    core       : core;
    on_signal  : World.t -> 'signal -> unit;
    on_event   : World.t -> 'event -> unit;
    on_command : World.t -> 'command -> unit;
    kind       : kind;  (** new field! *)
  }

  type ('s, 'e, 'c) t = ('s, 'e, 'c) reactive

  val ignore_signal  : 'a -> 'b -> unit
  val ignore_event   : 'a -> 'b -> unit
  val ignore_command : 'a -> 'b -> unit

  val make_core :
    ?register:(World.t -> unit) ->
    ?update:(World.t -> float -> unit) ->
    unit -> core

  val make_reactive :
    ?register:(World.t -> unit) ->
    ?update:(World.t -> float -> unit) ->
    ?on_signal:(World.t -> 's -> unit) ->
    ?on_event:(World.t -> 'e -> unit) ->
    ?on_command:(World.t -> 'c -> unit) ->
    ?kind : kind  ->  (** default = variable **)
    unit -> ('s, 'e, 'c) reactive

  val make_with_kind :
    kind -> core -> ('s, 'e, 'c) t

  val from_core : core -> ('s, 'e, 'c) reactive
  val attach_handlers :
    ?signals:'s Signal_bus.t ->
    ?events:'e Event_bus.t ->
    ?commands:'c Command_bus.t ->
    World.t -> ('s, 'e, 'c) reactive -> ('s, 'e, 'c) t
end

(* ====================================================================== *)
(* Implementation *)
(* ====================================================================== *)

module Make_with_kinds
    (Kinds : KIND)
    (Signal_bus  : Bus.BUS)
    (Event_bus   : Bus.BUS)
    (Command_bus : Bus.BUS)
  : S with type kind = Kinds.kind
       and module Signal_bus = Signal_bus
       and module Event_bus = Event_bus
       and module Command_bus = Command_bus
= struct
  module type BUS = Bus.BUS
  module Signal_bus = Signal_bus
  module Event_bus = Event_bus
  module Command_bus = Command_bus

  type core = {
    register : World.t -> unit;
    update   : World.t -> float -> unit;
  }

  type kind = Kinds.kind

  let make_core ?(register = fun _ -> ()) ?(update = fun _ _ -> ()) () =
    { register; update }

  type ('signal, 'event, 'command) reactive = {
    core       : core;
    on_signal  : World.t -> 'signal -> unit;
    on_event   : World.t -> 'event -> unit;
    on_command : World.t -> 'command -> unit;
    kind       : kind;
  }

  type ('s, 'e, 'c) t = ('s, 'e, 'c) reactive

  let ignore_signal  _ _ = ()
  let ignore_event   _ _ = ()
  let ignore_command _ _ = ()

  let make_reactive
      ?(register = fun _ -> ())
      ?(update = fun _ _ -> ())
      ?(on_signal = ignore_signal)
      ?(on_event = ignore_event)
      ?(on_command = ignore_command)
      ?(kind = Kinds.variable)
      ()
    =
    {
      core = { register; update };
      on_signal;
      on_event;
      on_command;
      kind;
    }

  let make_with_kind kind core =
    {
      core;
      on_signal = ignore_signal;
      on_event = ignore_event;
      on_command = ignore_command;
      kind;
    }

  let from_core (c : core) : ('s, 'e, 'c) reactive =
    {
      core = c;
      on_signal = ignore_signal;
      on_event = ignore_event;
      on_command = ignore_command;
      kind = Kinds.variable;
    }

  let to_core (r : ('s, 'e, 'c) reactive) : core = r.core

  let attach_handlers
      ?(signals : 's Signal_bus.t option)
      ?(events : 'e Event_bus.t option)
      ?(commands : 'c Command_bus.t option)
      (world : World.t)
      (sys : ('s, 'e, 'c) t)
    =
    let signals =
      match signals with
      | Some s -> s
      | None ->
         (match World.get_service world `Signals with
          | Some s -> s
          | None -> failwith "Missing signals service") in

    let events =
      match events with
      | Some e -> e
      | None ->
         (match World.get_service world `Events with
          | Some e -> e
          | None -> failwith "Missing events service") in

    let commands =
      match commands with
      | Some c -> c
      | None ->
         (match World.get_service world `Commands with
          | Some c -> c
          | None -> failwith "Missing commands service") in

    Signal_bus.on signals (fun msg -> sys.on_signal world msg);
    Event_bus.on events (fun msg -> sys.on_event world msg);
    Command_bus.on commands (fun msg -> sys.on_command world msg);
    sys
end

module Make
    (Signal_bus  : Bus.BUS)
    (Event_bus   : Bus.BUS)
    (Command_bus : Bus.BUS) =
  Make_with_kinds(Base_kind)(Signal_bus)(Event_bus)(Command_bus)

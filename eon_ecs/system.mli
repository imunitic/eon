(** ECS system definitions and reactive bus handlers.

    Systems are the units of logic in the ECS. A reactive system holds optional
    [register], [update], [on_signal], [on_event], and [on_command] callbacks.
    Use {!Make} (or the default alias {!Eon_ecs.System.Default}) to build a
    system module wired to a specific set of buses.

    Example:
    {[
      module System = Eon_ecs.System.Default

      let movement =
        System.make_reactive
          ~update:(fun world dt -> ignore (world, dt))
          ~kind:`Fixed
          ()
    ]}
*)

(** Kind tag interface used by {!Pipeline} and {!Progress} for scheduling.

    Exposes two canonical tags: [fixed] for deterministic fixed-step systems
    and [variable] for frame-rate-dependent systems. *)
module type KIND = sig
  type kind
  val fixed    : kind
  val variable : kind
end

(** Built-in kind mapping covering the [[ `Fixed | `Variable ]] default tags. *)
module Base_kind : KIND with type kind = [ `Fixed | `Variable ]

(** Concrete kind alias used by the default stack. *)
type kind = Base_kind.kind

(** Full system signature produced by {!Make} and {!Make_with_kinds}. *)
module type S = sig
  (** Common bus module type. *)
  module type BUS = Bus.BUS

  (** Bus used for signals. *)
  module Signal_bus : BUS

  (** Bus used for events. *)
  module Event_bus : BUS

  (** Bus used for commands. *)
  module Command_bus : BUS

  (** Side-effect-free core callbacks ([register] runs once; [update] runs each tick). *)
  type core = {
    register : World.t -> unit;
    update   : World.t -> float -> unit;
  }

  (** Kind tag attached to system instances. *)
  type kind

  (** Reactive system record bundling core callbacks, bus handlers, and a scheduling kind. *)
  type ('signal, 'event, 'command) reactive = {
    core       : core;
    on_signal  : World.t -> 'signal  -> unit;
    on_event   : World.t -> 'event   -> unit;
    on_command : World.t -> 'command -> unit;
    kind       : kind;
  }

  (** Alias for the reactive system type. *)
  type ('s, 'e, 'c) t = ('s, 'e, 'c) reactive

  (** No-op signal, event, and command handlers. *)
  val ignore_signal  : 'a -> 'b -> unit
  val ignore_event   : 'a -> 'b -> unit
  val ignore_command : 'a -> 'b -> unit

  (** Build a core from optional [register] and [update] callbacks. *)
  val make_core :
    ?register:(World.t -> unit) ->
    ?update:(World.t -> float -> unit) ->
    unit -> core

  (** Build a reactive system from optional callbacks. [kind] defaults to variable. *)
  val make_reactive :
    ?register:(World.t -> unit) ->
    ?update:(World.t -> float -> unit) ->
    ?on_signal:(World.t -> 's -> unit) ->
    ?on_event:(World.t -> 'e -> unit) ->
    ?on_command:(World.t -> 'c -> unit) ->
    ?kind:kind ->
    unit -> ('s, 'e, 'c) reactive

  (** Lift a [core] into a reactive system with no-op handlers and explicit kind. *)
  val make_with_kind : kind -> core -> ('s, 'e, 'c) t

  (** Lift a [core] into a variable-kind reactive system with no-op handlers. *)
  val from_core : core -> ('s, 'e, 'c) reactive

  (** Register bus handlers for this system.

      If a bus is not provided explicitly, reads it from the world via the
      corresponding service key ([\`Signals], [\`Events], [\`Commands]).

      @raise Failure if a required service is not registered in the world. *)
  val attach_handlers :
    ?signals:'s Signal_bus.t ->
    ?events:'e Event_bus.t ->
    ?commands:'c Command_bus.t ->
    World.t -> ('s, 'e, 'c) reactive -> ('s, 'e, 'c) t
end

(** Build a system module over custom bus implementations and a custom kind set. *)
module Make_with_kinds
    (Kinds       : KIND)
    (Signal_bus  : Bus.BUS)
    (Event_bus   : Bus.BUS)
    (Command_bus : Bus.BUS)
  : S with type kind = Kinds.kind
       and module Signal_bus  = Signal_bus
       and module Event_bus   = Event_bus
       and module Command_bus = Command_bus

(** Build a system module over custom bus implementations using the default kinds. *)
module Make
    (Signal_bus  : Bus.BUS)
    (Event_bus   : Bus.BUS)
    (Command_bus : Bus.BUS)
  : S with type kind = kind
       and module Signal_bus  = Signal_bus
       and module Event_bus   = Event_bus
       and module Command_bus = Command_bus

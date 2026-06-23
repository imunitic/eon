(** ECS system definitions and reactive bus handlers.

    Systems are the units of logic in the ECS. A reactive system holds optional
    [register], [update], [on_signal], [on_event], and [on_command] callbacks.
    Use {!Make} (or the default alias {!Eon_ecs.System.Default}) to build a
    system module wired to a specific set of buses.

    Example:
    {[
      module System = Eon_ecs.System.Default

      let movement =
        System.make
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
  module type BUS = Bus.S

  (** Bus used for signals. *)
  module Signal_bus : BUS

  (** Bus used for events. *)
  module Event_bus : BUS

  (** Bus used for commands. *)
  module Command_bus : BUS

  (** Kind tag attached to system instances. *)
  type kind

  (** Variable-step kind tag (the default). *)
  val variable : kind

  (** Fixed-step kind tag. *)
  val fixed : kind

  (** Opaque system value. *)
  type ('s, 'e, 'c) t

  (** Build a system from optional callbacks. [kind] defaults to [variable].

      All callbacks are optional — omit [on_signal], [on_event], [on_command]
      for a non-reactive system; omit [update] for a handler-only system. *)
  val make :
    ?register:(World.t -> unit) ->
    ?update:(World.t -> float -> unit) ->
    ?on_signal:(World.t -> 's -> unit) ->
    ?on_event:(World.t -> 'e -> unit) ->
    ?on_command:(World.t -> 'c -> unit) ->
    ?kind:kind ->
    unit -> ('s, 'e, 'c) t

  (** Scheduling kind of this system instance. *)
  val kind_of : ('s, 'e, 'c) t -> kind

  (** Run the [register] callback. Called once during pipeline setup. *)
  val register : ('s, 'e, 'c) t -> World.t -> unit

  (** Run the [update] callback. Called each tick by the pipeline. *)
  val run : ('s, 'e, 'c) t -> World.t -> float -> unit

  (** Subscribe this system's bus handlers to the given bus instances.

      Called automatically by [Pipeline.register_all]. Only call directly
      when wiring systems outside a pipeline. *)
  val attach :
    ('s, 'e, 'c) t -> World.t ->
    signals:'s Signal_bus.t ->
    events:'e Event_bus.t ->
    commands:'c Command_bus.t -> unit
end

(** Build a system module over custom bus implementations and a custom kind set. *)
module Make_with_kinds
    (Kinds       : KIND)
    (Signal_bus  : Bus.S)
    (Event_bus   : Bus.S)
    (Command_bus : Bus.S)
  : S with type kind = Kinds.kind
       and module Signal_bus  = Signal_bus
       and module Event_bus   = Event_bus
       and module Command_bus = Command_bus

(** Build a system module over custom bus implementations using the default kinds. *)
module Make
    (Signal_bus  : Bus.S)
    (Event_bus   : Bus.S)
    (Command_bus : Bus.S)
  : S with type kind = kind
       and module Signal_bus  = Signal_bus
       and module Event_bus   = Event_bus
       and module Command_bus = Command_bus

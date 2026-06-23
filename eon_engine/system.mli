(** Engine system — wraps any [Eon_ecs.System.S] with [World] capabilities.

    Each system declares whether its update runs in parallel ([ro] world view,
    via [Executor]) or exclusively ([rw] world view, sequential after parallel
    systems complete in the same phase). *)

(** Determines how a system's update is dispatched by the pipeline.

    - [Parallel]: update receives [World.ro World.t]; runs concurrently via
      [Executor]. Multiple parallel systems in a phase run in parallel.
    - [Exclusive]: update receives [World.rw World.t]; runs sequentially after
      all parallel systems in the phase have completed. Same model as Bevy's
      exclusive systems. *)
type update_kind =
  | Parallel  of (World.ro World.t -> float -> unit)
  | Exclusive of (World.rw World.t -> float -> unit)

(** User-facing interface. Game code only ever sees [make], [type t], and
    [type kind] through this signature — dispatch operations are hidden. *)
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

(** Pipeline-internal interface. [Pipeline.Make] takes [System : DISPATCH].
    [eon_engine.mli] constrains [System.Default] to [S] so game code never
    sees these operations directly. *)
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

(** Build an engine system module over any [Eon_ecs.System.S] implementation.
    The resulting module satisfies [DISPATCH] and can be passed to
    [Pipeline.Make]. Use bus type constraints on [Core_system] to wire custom
    signal / event / command buses. *)
module Make (Core_system : Eon_ecs.System.S) : DISPATCH
  with type kind = Core_system.kind
   and module Signal_bus  = Core_system.Signal_bus
   and module Event_bus   = Core_system.Event_bus
   and module Command_bus = Core_system.Command_bus

(** Default engine system wired with [Single_bus] (signals, commands) and
    [Double_bus] (events). Satisfies [DISPATCH]; constrained to [S] in
    [eon_engine.mli] so game code only sees [make]. *)
module Default : DISPATCH
  with type kind = [ `Fixed | `Variable ]
   and module Signal_bus  = Single_bus
   and module Event_bus   = Double_bus
   and module Command_bus = Single_bus

(** Engine system — wraps any [Eon_ecs.System.S] with [World_cap] capabilities.

    Each system declares whether its update runs in parallel ([ro] world view,
    via [Executor]) or exclusively ([rw] world view, sequential after parallel
    systems complete in the same phase). *)

(** Determines how a system's update is dispatched by the pipeline.

    - [Parallel]: update receives [ro World_cap.t]; runs concurrently via
      [Executor]. Multiple parallel systems in a phase run in parallel.
    - [Exclusive]: update receives [rw World_cap.t]; runs sequentially after
      all parallel systems in the phase have completed. Same model as Bevy's
      exclusive systems. *)
type update_kind =
  | Parallel  of (World_cap.ro World_cap.t -> float -> unit)
  | Exclusive of (World_cap.rw World_cap.t -> float -> unit)

(** User-facing interface. Game code only ever sees [make], [type t], and
    [type kind] through this signature — dispatch operations are hidden. *)
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

(** Pipeline-internal interface. [Pipeline.Make] takes [System : DISPATCH].
    [eon_engine.mli] constrains [System.Default] to [S] so game code never
    sees these operations directly. *)
module type DISPATCH = sig
  include S

  val kind_of     : ('s, 'e, 'c) t -> kind
  val is_parallel : ('s, 'e, 'c) t -> bool
  val update_ro   : ('s, 'e, 'c) t -> World_cap.ro World_cap.t -> float -> unit
  val update_rw   : ('s, 'e, 'c) t -> World_cap.rw World_cap.t -> float -> unit
  val attach      : ('s, 'e, 'c) t -> World.t -> unit
end

(** Build an engine system module over any [Eon_ecs.System.S] implementation.
    The resulting module satisfies [DISPATCH] and can be passed to
    [Pipeline.Make]. Use bus type constraints on [Core_system] to wire custom
    signal / event / command buses. *)
module Make (Core_system : Eon_ecs.System.S) : DISPATCH
  with type kind = Core_system.kind

(** Default engine system wired with [Single_bus] (signals, commands) and
    [Double_bus] (events). Satisfies [DISPATCH]; constrained to [S] in
    [eon_engine.mli] so game code only sees [make]. *)
module Default : DISPATCH

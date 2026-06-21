(** Time-step progression manager for engine pipelines.

    Mirrors [Eon_ecs.Progress] but typed for [World.t] and [Pipeline.S].
    Supports variable, fixed, and hybrid time modes.

    Example:
    {[
      module Progress = Eon_engine.Progress.Make(Eon_engine.Pipeline.Default)
      let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
    ]}
*)

(** {1 Abstract Time Modes} *)

module type TIME_MODE = sig
  type t
  type kind
  val create  : unit -> t
  val advance :
    t ->
    world:World.t ->
    dt:float ->
    run:(world:World.t -> kind:kind -> dt:float -> World.t) ->
    t * World.t
end

(** {1 Concrete Time Modes} *)

module Variable : sig
  module Make (K : Eon_ecs.System.KIND) : TIME_MODE with type kind = K.kind
  include TIME_MODE with type kind = [ `Fixed | `Variable ]
end

module Fixed : sig
  module Make (K : Eon_ecs.System.KIND) : sig
    include TIME_MODE with type kind = K.kind
    val with_step : float -> t
  end
  include TIME_MODE with type kind = [ `Fixed | `Variable ]
  val with_step : float -> t
end

module Hybrid : sig
  module Make (K : Eon_ecs.System.KIND) : sig
    include TIME_MODE with type kind = K.kind
    val with_step : float -> t
  end
  include TIME_MODE with type kind = [ `Fixed | `Variable ]
  val with_step : float -> t
end

(** {1 Unified Progress Controller} *)

module Make_with_kind
    (Kind : Eon_ecs.System.KIND)
    (Pipeline : Pipeline.S with type kind = Kind.kind) : sig

  type custom_mode =
    | Mode :
        { init    : unit -> 'state;
          advance : 'state ->
                    world:World.t ->
                    dt:float ->
                    run:(world:World.t -> kind:Pipeline.kind -> dt:float -> World.t) ->
                    'state * World.t;
        } -> custom_mode

  type mode =
    | Variable
    | Fixed  of float
    | Hybrid of float
    | Custom of custom_mode

  type 'phase t
  type world = World.t

  val create : ?mode:mode -> 'phase Pipeline.t -> 'phase t
  val tick   : 'phase t -> world:World.t -> dt:float -> World.t
end

(** Convenience functor wiring the progress controller to the default kinds. *)
module Make (Pipeline : Pipeline.S with type kind = [ `Fixed | `Variable ]) :
  module type of Make_with_kind(Eon_ecs.System.Base_kind)(Pipeline)

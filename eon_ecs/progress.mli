(** Eon ECS — Progress
    ------------------------------------------------------------------
    Time-step progression manager for running ECS pipelines.
    Supports fixed, variable, and hybrid modes.
    ------------------------------------------------------------------ *)

(** {1 Abstract Time Modes} *)

module type TIME_MODE = sig
  (** Opaque type representing the mode’s internal accumulator/state. *)
  type t

  (** Create a new mode instance. *)
  val create : unit -> t

  (** Advance one step. 
      @param world the ECS world to update
      @param dt delta time (in seconds)
      @param run_fixed callback for fixed-step updates
      @param run_variable callback for variable-step updates
      @return the updated world *)
  val advance :
    t ->
    world:World.t ->
    dt:float ->
    run_fixed:(World.t -> float -> World.t) ->
    run_variable:(World.t -> float -> World.t) ->
    World.t
end

(** {1 Concrete Time Modes} *)

(** Variable time-step progression. *)
module Variable : TIME_MODE

(** Fixed time-step progression with an accumulator. *)
module Fixed : sig
  include TIME_MODE
  val with_step : float -> t
  (** Create a fixed mode with the given step size (seconds). *)
end

(** Hybrid progression: fixed logic + variable updates. *)
module Hybrid : sig
  include TIME_MODE
  val with_step : float -> t
  (** Create a hybrid mode with the given fixed step size. *)
end

(** {1 Unified Progress Controller} *)

module Make (Pipeline : Pipeline.S) : sig
  (** Supported simulation modes. *)
  type mode =
    | Variable
    | Fixed of float
    | Hybrid of float

  (** Progress controller state. *)
  type 'phase t

  (** Create a progress controller for a pipeline and chosen mode. *)
  val create : ?mode:mode -> 'phase Pipeline.t -> 'phase t

  (** Advance one frame.
      @param t progress controller
      @param world the ECS world
      @param dt delta time (in seconds)
      @return updated world after all pipeline systems have run *)
  val tick : 'phase t -> world:World.t -> dt:float -> World.t
end

(** Time-step progression manager for ECS pipelines.

    {!Make} and {!Make_with_kind} provide a controller that advances systems
    according to mode selection.

    Example with default stack:
    {[
      module Pipeline = Eon_ecs.Pipeline.Default
      module Progress = Eon_ecs.Progress.Default

      let pipeline = Pipeline.create () |> Pipeline.add_phase `Gameplay
      let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
    ]}
*)

(** {1 Abstract Time Modes} *)

module type TIME_MODE = sig
  (** Opaque type representing the mode’s internal accumulator/state. *)
  type t

  (** Kind tag used to dispatch systems within the pipeline. *)
  type kind

  (** Create a new mode instance. *)
  val create : unit -> t

  (** Advance one step.
      @param world the ECS world to update
      @param dt delta time (in seconds)
      @param run callback used to execute pipeline systems for a given kind/tag
      @return the updated mode state and world *)
  val advance :
    t ->
    world:World.t ->
    dt:float ->
    run:(world:World.t -> kind:kind -> dt:float -> World.t) ->
    t * World.t
end

(** {1 Concrete Time Modes} *)

module Variable : sig
  module type KIND = sig
    (** Abstract mapping of fixed/variable kinds to pipeline tags. *)
    type kind
    (** Tag associated with fixed-step system execution. *)
    val fixed : kind
    (** Tag associated with variable-step system execution. *)
    val variable : kind
  end
  (** Functor producing a variable-step mode for a custom kind mapping. *)
  module Make : functor (K : KIND) -> TIME_MODE with type kind = K.kind

  (** Default variable-step mode using {!System.kind} tags. *)
  include TIME_MODE with type kind = System.kind
end

module Fixed : sig
  module type KIND = sig
    (** Abstract mapping of fixed/variable kinds to pipeline tags. *)
    type kind
    (** Tag associated with fixed-step system execution. *)
    val fixed : kind
    (** Tag associated with variable-step system execution. *)
    val variable : kind
  end
  module Make : functor (K : KIND) -> sig
    include TIME_MODE with type kind = K.kind
    (** Instantiate a fixed-step mode with the provided step duration. *)
    val with_step : float -> t
  end
  (** Default fixed-step mode using {!System.kind} tags. *)
  include TIME_MODE with type kind = System.kind

  (** Instantiate the default fixed-step mode with a step duration in seconds. *)
  val with_step : float -> t
end

module Hybrid : sig
  module type KIND = sig
    (** Abstract mapping of fixed/variable kinds to pipeline tags. *)
    type kind
    (** Tag associated with fixed-step system execution. *)
    val fixed : kind
    (** Tag associated with variable-step system execution. *)
    val variable : kind
  end
  module Make : functor (K : KIND) -> sig
    include TIME_MODE with type kind = K.kind
    (** Instantiate a hybrid mode with the provided fixed-step duration. *)
    val with_step : float -> t
  end
  (** Default hybrid mode using {!System.kind} tags. *)
  include TIME_MODE with type kind = System.kind

  (** Instantiate the default hybrid mode with a fixed-step duration. *)
  val with_step : float -> t
end

(** {1 Unified Progress Controller} *)

module Make_with_kind
    (Kind : System.KIND)
    (Pipeline : Pipeline.S with type kind = Kind.kind) : sig
  (** Internal packaging of a time mode. *)
  type custom_mode =
    | Mode :
        {
          init : unit -> 'state;
          advance :
            'state ->
            world:World.t ->
            dt:float ->
            run:(world:World.t -> kind:Pipeline.kind -> dt:float -> World.t) ->
            'state * World.t;
        } -> custom_mode

  (** Supported simulation modes. *)
  type mode =
    | Variable
    | Fixed of float
    | Hybrid of float
    | Custom of custom_mode

  (** Progress controller state. *)
  type 'phase t

  (** Create a progress controller for a pipeline and chosen mode. *)
  val create : ?mode:mode -> 'phase Pipeline.t -> 'phase t

  (** Advance one frame.
      @param t progress controller
      @param world the ECS world
      @param dt delta time (in seconds)
      @return updated world after all pipeline systems have run

      Example:
      {[
        let world' = Progress.tick progress ~world ~dt:0.016
      ]}
  *)
  val tick : 'phase t -> world:World.t -> dt:float -> World.t
end

(** Convenience functor wiring the progress controller to the default kinds. *)
module Make (Pipeline : Pipeline.S with type kind = System.kind) :
  module type of Make_with_kind(System.Base_kind)(Pipeline)

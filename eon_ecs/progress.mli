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

module type S = sig
  (** Opaque type representing the mode's internal accumulator/state. *)
  type t

  (** Kind tag used to dispatch systems within the pipeline. *)
  type kind

  (** World type this mode operates on. *)
  type world

  (** Create a new mode instance. *)
  val create : unit -> t

  (** Advance one step.
      @param world the ECS world to update
      @param dt delta time (in seconds)
      @param run callback used to execute pipeline systems for a given kind/tag
      @return the updated mode state and world *)
  val advance :
    t ->
    world:world ->
    dt:float ->
    run:(world:world -> kind:kind -> dt:float -> world) ->
    t * world
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
  (** Functor producing a variable-step mode for a custom kind and world type. *)
  module Make (K : KIND) (W : sig type t end) :
    S with type kind = K.kind and type world = W.t

  (** Default variable-step mode using {!System.kind} tags and {!World.t}. *)
  include S with type kind = System.kind and type world = World.t
end

module Fixed : sig
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end
  module Make (K : KIND) (W : sig type t end) : sig
    include S with type kind = K.kind and type world = W.t
    (** Instantiate a fixed-step mode with the provided step duration. *)
    val with_step : float -> t
  end
  (** Default fixed-step mode using {!System.kind} tags and {!World.t}. *)
  include S with type kind = System.kind and type world = World.t
  val with_step : float -> t
end

module Hybrid : sig
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end
  module Make (K : KIND) (W : sig type t end) : sig
    include S with type kind = K.kind and type world = W.t
    (** Instantiate a hybrid mode with the provided fixed-step duration. *)
    val with_step : float -> t
  end
  (** Default hybrid mode using {!System.kind} tags and {!World.t}. *)
  include S with type kind = System.kind and type world = World.t
  val with_step : float -> t
end

(** {1 Unified Progress Controller} *)

module Make_with_kind
    (Kind : System.KIND)
    (Pipeline : Pipeline.S with type kind = Kind.kind) : sig
  (** Supported simulation modes. *)
  type mode =
    | Variable
    | Fixed of float
    | Hybrid of float

  (** Progress controller state. *)
  type 'phase t

  type world = Pipeline.world

  (** Create a progress controller for a pipeline and chosen mode. *)
  val create : ?mode:mode -> 'phase Pipeline.t -> 'phase t

  (** Advance one frame.
      @param t progress controller
      @param world the ECS world
      @param dt delta time (in seconds)
      @return updated world after all pipeline systems have run *)
  val tick : 'phase t -> world:Pipeline.world -> dt:float -> Pipeline.world
end

(** Convenience functor wiring the progress controller to the default kinds. *)
module Make (Pipeline : Pipeline.S with type kind = System.kind) :
  module type of Make_with_kind(System.Base_kind)(Pipeline)

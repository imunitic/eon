(** Eon ECS — Progress
    ------------------------------------------------------------------
    Time-step progression manager for running ECS pipelines.
    Supports fixed, variable, and hybrid modes.
    ------------------------------------------------------------------ *)

module type S = sig
  type t
  type kind
  type world

  val create : unit -> t

  val advance :
    t ->
    world:world ->
    dt:float ->
    run:(world:world -> kind:kind -> dt:float -> world) ->
    t * world
end

module Variable = struct
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end

  module Make (K : KIND) (W : sig type t end)
    : S with type kind = K.kind and type world = W.t = struct
    type kind = K.kind
    type world = W.t
    type t = unit

    let create () = ()

    let advance t ~world ~dt ~run =
      let world' = run ~world ~kind:K.variable ~dt in
      (t, world')
  end

  module Default_kind = struct
    type kind = System.kind
    let fixed : kind = `Fixed
    let variable : kind = `Variable
  end

  module Impl = Make (Default_kind) (struct type t = World.t end)
  include Impl
end

module Fixed = struct
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end

  module Make (K : KIND) (W : sig type t end) : sig
    include S with type kind = K.kind and type world = W.t
    val with_step : float -> t
  end = struct
    type kind = K.kind
    type world = W.t
    type t = {
        step : float;
        mutable accumulator : float;
      }

    let create () = { step = 1.0 /. 60.0; accumulator = 0.0 }
    let with_step step = { step; accumulator = 0.0 }

    let advance t ~world ~dt ~run =
      t.accumulator <- t.accumulator +. dt;
      let world_ref = ref world in
      let epsilon = 1e-8 in
      while t.accumulator +. epsilon >= t.step do
        world_ref := run ~world:!world_ref ~kind:K.fixed ~dt:t.step;
        t.accumulator <- t.accumulator -. t.step
      done;
      (t, !world_ref)
  end

  module Default_kind = struct
    type kind = System.kind
    let fixed : kind = `Fixed
    let variable : kind = `Variable
  end

  module Impl = Make (Default_kind) (struct type t = World.t end)
  include Impl
end

module Hybrid = struct
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end

  module Make (K : KIND) (W : sig type t end) : sig
    include S with type kind = K.kind and type world = W.t
    val with_step : float -> t
  end = struct
    type kind = K.kind
    type world = W.t
    type t = {
        step : float;
        mutable accumulator : float;
      }

    let create () = { step = 1.0 /. 60.0; accumulator = 0.0 }
    let with_step step = { step; accumulator = 0.0 }

    let advance t ~world ~dt ~run =
      t.accumulator <- t.accumulator +. dt;
      let world_ref = ref world in
      let epsilon = 1e-8 in
      while t.accumulator +. epsilon >= t.step do
        world_ref := run ~world:!world_ref ~kind:K.fixed ~dt:t.step;
        t.accumulator <- t.accumulator -. t.step
      done;
      let world' = run ~world:!world_ref ~kind:K.variable ~dt in
      (t, world')
  end

  module Default_kind = struct
    type kind = System.kind
    let fixed : kind = `Fixed
    let variable : kind = `Variable
  end

  module Impl = Make (Default_kind) (struct type t = World.t end)
  include Impl
end

module Make_with_kind
    (Kind : System.KIND)
    (Pipeline : Pipeline.S with type kind = Kind.kind)
= struct
  module Variable_mode = Variable.Make (Kind) (struct type t = Pipeline.world end)
  module Fixed_mode    = Fixed.Make    (Kind) (struct type t = Pipeline.world end)
  module Hybrid_mode   = Hybrid.Make   (Kind) (struct type t = Pipeline.world end)

  type world = Pipeline.world

  type custom_mode =
    | Mode :
        { init    : unit -> 'state;
          advance : 'state ->
                    world:world ->
                    dt:float ->
                    run:(world:world -> kind:Pipeline.kind -> dt:float -> world) ->
                    'state * world;
        } -> custom_mode

  type mode =
    | Variable
    | Fixed  of float
    | Hybrid of float
    | Custom of custom_mode

  type mode_state =
    | Mode_state :
        { mutable state : 'state;
          advance : 'state ->
                    world:world ->
                    dt:float ->
                    run:(world:world -> kind:Pipeline.kind -> dt:float -> world) ->
                    'state * world;
        } -> mode_state

  type 'phase t = {
    mode     : mode_state;
    pipeline : 'phase Pipeline.t;
  }

  let instantiate_mode = function
    | Variable ->
      Mode_state { state = Variable_mode.create (); advance = Variable_mode.advance }
    | Fixed step ->
      Mode_state { state = Fixed_mode.with_step step; advance = Fixed_mode.advance }
    | Hybrid step ->
      Mode_state { state = Hybrid_mode.with_step step; advance = Hybrid_mode.advance }
    | Custom (Mode m) ->
      Mode_state { state = m.init (); advance = m.advance }

  let create ?(mode = Variable) pipeline =
    { mode = instantiate_mode mode; pipeline }

  let tick t ~world ~dt =
    let run ~world ~kind ~dt =
      Pipeline.run_by_filter ~filter:(fun k -> k = kind) t.pipeline world dt
    in
    let Mode_state mode = t.mode in
    let state', world' = mode.advance mode.state ~world ~dt ~run in
    mode.state <- state';
    world'
end

module Make (Pipeline : Pipeline.S with type kind = System.kind) =
  Make_with_kind (System.Base_kind) (Pipeline)

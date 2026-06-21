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

module Variable = struct
  module Make (K : Eon_ecs.System.KIND) : TIME_MODE with type kind = K.kind = struct
    type kind = K.kind
    type t = unit
    let create () = ()
    let advance t ~world ~dt ~run =
      let world' = run ~world ~kind:K.variable ~dt in
      (t, world')
  end

  module Impl = Make (Eon_ecs.System.Base_kind)
  include Impl
end

module Fixed = struct
  module Make (K : Eon_ecs.System.KIND) : sig
    include TIME_MODE with type kind = K.kind
    val with_step : float -> t
  end = struct
    type kind = K.kind
    type t = { step : float; mutable accumulator : float }
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

  module Impl = Make (Eon_ecs.System.Base_kind)
  include Impl
end

module Hybrid = struct
  module Make (K : Eon_ecs.System.KIND) : sig
    include TIME_MODE with type kind = K.kind
    val with_step : float -> t
  end = struct
    type kind = K.kind
    type t = { step : float; mutable accumulator : float }
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

  module Impl = Make (Eon_ecs.System.Base_kind)
  include Impl
end

module Make_with_kind
    (Kind : Eon_ecs.System.KIND)
    (Pipeline : Pipeline.S with type kind = Kind.kind)
= struct
  module Variable_mode = Variable.Make (Kind)
  module Fixed_mode    = Fixed.Make (Kind)
  module Hybrid_mode   = Hybrid.Make (Kind)

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

  type mode_state =
    | Mode_state :
        { mutable state : 'state;
          advance : 'state ->
                    world:World.t ->
                    dt:float ->
                    run:(world:World.t -> kind:Pipeline.kind -> dt:float -> World.t) ->
                    'state * World.t;
        } -> mode_state

  type 'phase t = {
    mode     : mode_state;
    pipeline : 'phase Pipeline.t;
  }

  type world = World.t

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

module Make (Pipeline : Pipeline.S with type kind = [ `Fixed | `Variable ]) =
  Make_with_kind (Eon_ecs.System.Base_kind) (Pipeline)

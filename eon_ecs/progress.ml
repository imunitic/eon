(** Eon ECS — Progress
    ------------------------------------------------------------------
    Time-step progression manager for running ECS pipelines.
    Supports fixed, variable, and hybrid modes.
    ------------------------------------------------------------------ *)

(* ================================================================ *)
(* 🔹 Abstract TIME_MODE interface *)
(* ================================================================ *)

module type TIME_MODE = sig
  type t
  type kind

  val create : unit -> t

  val advance :
    t ->
    world:World.t ->
    dt:float ->
    run:(world:World.t -> kind:kind -> dt:float -> World.t) ->
    t * World.t
end

(* ================================================================ *)
(* 🔹 Generic Variable timestep mode *)
(* ================================================================ *)

module Variable = struct
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end

  module Make (K : KIND) : TIME_MODE with type kind = K.kind = struct
    type kind = K.kind
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

  module Impl = Make (Default_kind)
  include Impl
end

(* ================================================================ *)
(* 🔹 Generic Fixed timestep mode *)
(* ================================================================ *)

module Fixed = struct
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end

  module Make (K : KIND) : sig
    include TIME_MODE with type kind = K.kind
    val with_step : float -> t
  end = struct
    type kind = K.kind
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

  module Impl = Make (Default_kind)
  include Impl
end

(* ================================================================ *)
(* 🔹 Generic Hybrid timestep mode *)
(* ================================================================ *)

module Hybrid = struct
  module type KIND = sig
    type kind
    val fixed : kind
    val variable : kind
  end

  module Make (K : KIND) : sig
    include TIME_MODE with type kind = K.kind
    val with_step : float -> t
  end = struct
    type kind = K.kind
    type t = {
        step : float;
        mutable accumulator : float;
      }

    let create () = { step = 1.0 /. 60.0; accumulator = 0.0 }
    let with_step step = { step; accumulator = 0.0 }

    let advance t ~world ~dt ~run =
      (* Run fixed-step updates first *)
      t.accumulator <- t.accumulator +. dt;
      let world_ref = ref world in
      let epsilon = 1e-8 in
      while t.accumulator +. epsilon >= t.step do
        world_ref := run ~world:!world_ref ~kind:K.fixed ~dt:t.step;
        t.accumulator <- t.accumulator -. t.step
      done;
      (* Then variable systems after fixed-step logic *)
      let world' = run ~world:!world_ref ~kind:K.variable ~dt in
      (t, world')
  end

  module Default_kind = struct
    type kind = System.kind
    let fixed : kind = `Fixed
    let variable : kind = `Variable
  end

  module Impl = Make (Default_kind)
  include Impl
end

(* ================================================================ *)
(* 🔹 Unified Progress Controller *)
(* ================================================================ *)

module Make_with_kind
    (Kind : System.KIND)
    (Pipeline : Pipeline.S with type kind = Kind.kind)
= struct
  module Variable_mode = Variable.Make (Kind)
  module Fixed_mode = Fixed.Make (Kind)
  module Hybrid_mode = Hybrid.Make (Kind)
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

  type mode =
    | Variable
    | Fixed of float
    | Hybrid of float
    | Custom of custom_mode

  type mode_state =
    | Mode_state :
        {
          mutable state : 'state;
          advance :
            'state ->
            world:World.t ->
            dt:float ->
            run:(world:World.t -> kind:Pipeline.kind -> dt:float -> World.t) ->
            'state * World.t;
        } -> mode_state

  type 'phase t = {
      mode : mode_state;
      pipeline : 'phase Pipeline.t;
    }

  let instantiate_mode = function
    | Variable ->
       Mode_state
         {
           state = Variable_mode.create ();
           advance = Variable_mode.advance;
         }
    | Fixed step ->
       Mode_state
         {
           state = Fixed_mode.with_step step;
           advance = Fixed_mode.advance;
         }
    | Hybrid step ->
       Mode_state
         {
           state = Hybrid_mode.with_step step;
           advance = Hybrid_mode.advance;
         }
    | Custom (Mode mode) ->
       Mode_state
         {
           state = mode.init ();
           advance = mode.advance;
         }

  let create ?(mode = Variable) pipeline =
    let mode_state = instantiate_mode mode in
    { mode = mode_state; pipeline }

  let tick t ~world ~dt =
    let run ~world ~kind ~dt =
      Pipeline.run_by_filter
        ~filter:(fun k -> k = kind)
        t.pipeline
        world
        dt
    in
    let Mode_state mode = t.mode in
    let state', world' = mode.advance mode.state ~world ~dt ~run in
    mode.state <- state';
    world'
end

module Make (Pipeline : Pipeline.S with type kind = System.kind) =
  Make_with_kind (System.Base_kind) (Pipeline)

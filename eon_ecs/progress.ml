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

  val create : unit -> t

  val advance :
    t ->
    world:World.t ->
    dt:float ->
    run_fixed:(World.t -> float -> World.t) ->
    run_variable:(World.t -> float -> World.t) ->
    World.t
end

(* ================================================================ *)
(* 🔹 Variable timestep mode *)
(* ================================================================ *)

module Variable : TIME_MODE = struct
  type t = unit

  let create () = ()

  let advance _t ~world ~dt ~run_fixed:_ ~run_variable =
    run_variable world dt
end

(* ================================================================ *)
(* 🔹 Fixed timestep mode *)
(* ================================================================ *)

module Fixed : sig
  include TIME_MODE
  val with_step : float -> t
end = struct
  type t = {
      step : float;
      mutable accumulator : float;
    }

  let create () = { step = 1.0 /. 60.0; accumulator = 0.0 }
  let with_step step = { step; accumulator = 0.0 }

  let advance t ~world ~dt ~run_fixed ~run_variable:_ =
    t.accumulator <- t.accumulator +. dt;
    let world_ref = ref world in
    let epsilon = 1e-8 in
    while t.accumulator +. epsilon >= t.step do
      world_ref := run_fixed !world_ref t.step;
      t.accumulator <- t.accumulator -. t.step
    done;
    !world_ref
end

(* ================================================================ *)
(* 🔹 Hybrid timestep mode *)
(* ================================================================ *)

module Hybrid : sig
  include TIME_MODE
  val with_step : float -> t
end = struct
  type t = {
      step : float;
      mutable accumulator : float;
    }

  let create () = { step = 1.0 /. 60.0; accumulator = 0.0 }
  let with_step step = { step; accumulator = 0.0 }

  let advance t ~world ~dt ~run_fixed ~run_variable =
    (* Run fixed-step updates first *)
    t.accumulator <- t.accumulator +. dt;
    let world_ref = ref world in
    let epsilon = 1e-8 in
    while t.accumulator +. epsilon >= t.step do
      world_ref := run_fixed !world_ref t.step;
      t.accumulator <- t.accumulator -. t.step
    done;
    (* Then variable systems after fixed-step logic *)
    run_variable !world_ref dt
end

(* ================================================================ *)
(* 🔹 Unified Progress Controller *)
(* ================================================================ *)

module Make (Pipeline : Pipeline.S) = struct
  type mode =
    | Variable
    | Fixed of float
    | Hybrid of float

  type 'phase t = {
      mode : mode_state;
      pipeline: 'phase Pipeline.t;
    }
  and mode_state =
    | Var of Variable.t
    | Fix of Fixed.t
    | Hyb of Hybrid.t
  
  let create ?(mode = Variable) pipeline =
    let mode_state =
      match mode with
      | Variable -> Var (Variable.create ())
      | Fixed step -> Fix (Fixed.with_step step)
      | Hybrid step -> Hyb (Hybrid.with_step step)
    in
    { mode = mode_state; pipeline }
  
  let tick t ~world ~dt =
    match t.mode with
    | Var v ->
       Variable.advance v ~world ~dt
         ~run_fixed:(fun w _ -> w)
         ~run_variable:(fun w dt ->
           Pipeline.run_by_filter ~filter:(fun k -> k = `Variable) t.pipeline w dt)
    | Fix f ->
       Fixed.advance f ~world ~dt
         ~run_fixed:(fun w dt ->
           Pipeline.run_by_filter ~filter:(fun k -> k = `Fixed) t.pipeline w dt)
         ~run_variable:(fun w _ -> w)
    | Hyb h ->
       Hybrid.advance h ~world ~dt
         ~run_fixed:(fun w dt ->
           Pipeline.run_by_filter ~filter:(fun k -> k = `Fixed) t.pipeline w dt)
         ~run_variable:(fun w dt ->
           Pipeline.run_by_filter ~filter:(fun k -> k = `Variable) t.pipeline w dt)
end

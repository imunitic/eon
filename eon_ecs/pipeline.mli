(** Ordered execution graph for ECS systems.

    A pipeline holds a set of named phases, ordering constraints between them,
    and the systems assigned to each phase. On each tick the pipeline runs
    systems in topologically sorted phase order, filtered by kind.

    Example:
    {[
      module Pipeline = Eon_ecs.Pipeline.Default

      let pipeline =
        Pipeline.create ()
        |> Pipeline.add_phase `Input
        |> Pipeline.add_phase `Gameplay
        |> Pipeline.before ~earlier:`Input ~later:`Gameplay
    ]}
*)

(** Full pipeline signature produced by {!Make}. *)
module type S = sig
  (** Pipeline state keyed by phase values. *)
  type 'phase t

  (** System type stored in this pipeline implementation. *)
  type ('s, 'e, 'c) system_t

  (** Kind tag used for filtered execution. *)
  type kind

  (** World type this pipeline operates on. *)
  type world

  (** Create an empty pipeline. *)
  val create : unit -> 'phase t

  (** Add a phase if not already present. *)
  val add_phase : 'phase -> 'phase t -> 'phase t

  (** Declare [earlier] must run before [later]. *)
  val before : earlier:'phase -> later:'phase -> 'phase t -> 'phase t

  (** Declare [later] must run after [earlier]. *)
  val after : later:'phase -> earlier:'phase -> 'phase t -> 'phase t

  (** Attach a system to a phase.

      @raise Invalid_argument if the phase is not registered. *)
  val add_system : 'phase -> ('s, 'e, 'c) system_t -> 'phase t -> 'phase t

  (** Execute the [register] callback of every system in topological phase order. *)
  val register_all : 'phase t -> world -> unit

  (** Run systems whose kind satisfies [filter], in topological phase order.

      Used internally by {!Progress} to dispatch fixed or variable systems. *)
  val run_by_filter :
    filter:(kind -> bool) ->
    'phase t -> world -> float -> world

  (** Run all systems in topological phase order regardless of kind. *)
  val run : 'phase t -> world -> float -> world

  (** Return phases in resolved topological order. *)
  val phases : 'phase t -> 'phase list
end

(** Build a pipeline implementation over a concrete system module. *)
module Make (System : System.S) : S
  with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
   and type kind = System.kind
   and type world = World.t

(** Engine parallel pipeline — two-step dispatch via Executor.

    Each phase runs parallel systems first (via [Executor.run_all] with
    [ro World_cap.t]) then exclusive systems sequentially ([rw World_cap.t]).
    [World_cap] wrapping is entirely internal; [Progress] and [Loop] see only
    [World.t].

    Phase ordering uses [Eon_ecs.Dependency_graph] — the same topo-sort
    primitive as the core pipeline. *)

(** Common signature for pipeline instances. *)
module type S = sig
  type 'phase t
  type ('s, 'e, 'c) system_t
  type kind

  val create       : unit -> 'phase t
  val add_phase    : 'phase -> 'phase t -> 'phase t
  val before       : earlier:'phase -> later:'phase -> 'phase t -> 'phase t
  val after        : later:'phase  -> earlier:'phase -> 'phase t -> 'phase t
  val add_system   : 'phase -> ('s, 'e, 'c) system_t -> 'phase t -> 'phase t
  val register_all : 'phase t -> Eon_ecs.World.t -> unit
  val run          : 'phase t -> Eon_ecs.World.t -> float -> Eon_ecs.World.t
  val run_by_filter :
    filter:(kind -> bool) ->
    'phase t -> Eon_ecs.World.t -> float -> Eon_ecs.World.t
  val phases       : 'phase t -> 'phase list
end

[@@@warning "-67"]
(* Build a parallel pipeline over a [System.DISPATCH] implementation and an
   [Executor]. Swap [Executor.Sequential] for [Executor.Domain_pool] without
   changing system definitions. *)
module Make
    (System   : System.DISPATCH)
    (Executor : Executor.S)
  : S with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
       and type kind = System.kind
[@@@warning "+67"]

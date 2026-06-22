(** Engine parallel pipeline — two-step dispatch via Executor.

    Each phase runs parallel systems first (via [Executor.run_all] with
    [World.ro World.t]) then exclusive systems sequentially ([World.rw World.t]).
    Capability management is entirely internal; [Progress] and [Loop] see only
    [World.rw World.t].

    Phase ordering uses [Eon_ecs.Dependency_graph] — the same topo-sort
    primitive as the core pipeline. *)

(** Common signature for pipeline instances. *)
module type S = sig
  type 'phase t
  type ('s, 'e, 'c) system_t
  type kind
  type world

  val create       : unit -> 'phase t
  val add_phase    : 'phase -> 'phase t -> 'phase t
  val before       : earlier:'phase -> later:'phase -> 'phase t -> 'phase t
  val after        : later:'phase  -> earlier:'phase -> 'phase t -> 'phase t
  val add_system   : 'phase -> ('s, 'e, 'c) system_t -> 'phase t -> 'phase t
  val register_all : 'phase t -> world -> unit
  val run          : 'phase t -> world -> float -> world
  val run_by_filter :
    filter:(kind -> bool) ->
    'phase t -> world -> float -> world
  val phases       : 'phase t -> 'phase list
end

(* Warning 67 suppressed permanently: Executor.S has no types, only
   run_all — OCaml's functor-usage check only tracks type references, so
   Executor is invisible to it regardless of implementation. *)
[@@@warning "-67"]
module Make
    (System   : System.DISPATCH)
    (Executor : Executor.S)
  : S with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
       and type kind = System.kind
       and type world = World.rw World.t
[@@@warning "+67"]

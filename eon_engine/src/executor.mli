(** Threading-substrate seam for the parallel pipeline.

    [Executor.S] is the only place a threading library touches the pipeline.
    All scheduling logic stays in [Pipeline.Make]; the executor only receives
    a list of jobs and runs them.

    [run_all] is synchronous: it returns only after every job has finished.
    This makes the phase barrier automatic — after [run_all] returns, all
    parallel systems in the phase have completed and the next phase can begin.

    Swap the executor to change parallelism without touching any system code:
    - [Sequential]: single-threaded dispatch, identical to the core pipeline
    - [Domain_pool.Make]: OCaml 5 domains, true concurrent dispatch *)

module type S = sig
  (** Run all [jobs] and block until every one completes. *)
  val run_all : (unit -> unit) list -> unit
end

(** Sequential executor — [run_all] is [List.iter (fun f -> f ())].
    Degrades the parallel pipeline to exactly the core's sequential behaviour.
    Use as the default and for testing. *)
module Sequential : S

(** Parallel executor backed by a persistent pool of OCaml 5 [Domain]s. *)
module Domain_pool : sig
  (** Recommended worker count for the current machine: all logical cores minus
      Domain 0 (the main program domain), clamped to at least 1.
      For a game, prefer [max 1 (recommended_size () - 1)] to leave a core
      free for the render thread and OS work. *)
  val recommended_size : unit -> int

  (* [Make(Config)] spawns [Config.size] worker domains once at module
     instantiation, each mapping 1:1 to an OS thread pinned to a CPU core.
     [run_all] enqueues jobs, wakes workers, and blocks until all complete.
     If any job raises, the first captured exception is re-raised after all
     jobs have finished; other exceptions are discarded. *)
  [@@@warning "-67"]
  module Make (Config : sig val size : int end) : S
  [@@@warning "+67"]
end

(** Threading-substrate seam for the parallel pipeline.

    [Executor.S] is the only place a threading library touches the pipeline.
    All scheduling logic stays in [Pipeline.Make]; the executor only receives
    a list of jobs and runs them.

    [run_all] is synchronous: it returns only after every job has finished.
    This makes the phase barrier automatic — after [run_all] returns, all
    parallel systems in the phase have completed and the next phase can begin.

    Swap the executor to change parallelism without touching any system code:
    - [Sequential]: single-threaded dispatch, identical to the core pipeline
    - [Domain_pool] (future): OCaml 5 domains, true concurrent dispatch *)

module type S = sig
  (** Run all [jobs] and block until every one completes. *)
  val run_all : (unit -> unit) list -> unit
end

(** Sequential executor — [run_all] is [List.iter (fun f -> f ())].
    Degrades the parallel pipeline to exactly the core's sequential behaviour.
    Use as the default and for testing. *)
module Sequential : S

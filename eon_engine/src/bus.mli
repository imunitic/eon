(** Engine bus signature.

    Engine buses embed the corresponding [Eon_ecs] bus and add a [Mutex]
    on [emit] so parallel systems can safely enqueue messages during
    [Executor.run_all]. All other operations delegate to the inner bus
    and run sequentially outside the parallel phase window. *)

module type S = Eon_ecs.Bus.S

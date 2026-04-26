(** Internal sparse set backend implementation.
    
    This module is not part of the public API.
    Use Eon_engine.Sparse_set_backend instead.
*)

include Query_backend.S with type world = Eon_ecs.World.t
